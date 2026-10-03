// Bounded, descriptor-anchored reads. These helpers confer no provenance authority.
//
// Linux only. Every path component is opened relative to its parent's descriptor
// through /proc/self/fd/<fd>/<name> with O_NOFOLLOW, which is the only way Node
// can get openat() semantics. Other platforms have no equivalent (macOS /dev/fd
// does not resolve names through a directory descriptor), so they are refused
// with a distinct error before any I/O rather than served by a weaker walk that
// would report MATCH on a raceable path.
import { constants } from 'node:fs';
import { open, readdir, realpath } from 'node:fs/promises';
import { resolve, isAbsolute } from 'node:path';
import { createHash } from 'node:crypto';

const FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK | constants.O_NOATIME;
const FILE_LIMIT = 8 * 1024 * 1024;
const TOTAL_LIMIT = 128 * 1024 * 1024;
/** Documented defaults. Callers override them only through explicit arguments,
 * never through environment variables (an inherited variable is a redirect vector). */
export const DEFAULT_RUNTIME_ROOT = '/worker/runtime';
export const DEFAULT_WORKSPACE_ROOT = '/workspace';
export const UNSUPPORTED_PLATFORM = 'continuation_unsupported_platform';
/** Refuse every non-Linux platform before any filesystem access. */
export function assertSupportedPlatform(platform = process.platform) {
  if (platform !== 'linux') throw new Error(UNSUPPORTED_PLATFORM);
}
const fail = () => { throw new Error('continuation_workspace_unavailable'); };
const requireValue = value => { if (!value) fail(); };
const identity = info => ['dev', 'ino', 'mode', 'uid', 'gid', 'nlink', 'size', 'mtimeNs', 'ctimeNs']
  .map(key => String(info[key])).join(':');
const forbidden = /^(?:\.git|\.ssh|\.config|\.local|\.claude|\.codex|\.npmrc|\.netrc|\.env|auth(?:\..*)?|history|panes?|spools?|runtime|home|hooks|launch\.json)$/i;

export function sourceParts(path, directory = false) {
  requireValue(typeof path === 'string' && Buffer.byteLength(path) <= 1024 &&
    !/[\x00-\x1f\x7f\\]/.test(path) && !/[\ud800-\udfff]/u.test(path));
  const parts = path.split('/');
  requireValue(parts.length <= 32 && parts.every(part => part && part !== '.' && part !== '..' && Buffer.byteLength(part) <= 255));
  const name = parts.at(-1).toLowerCase(), example = /\.(example|sample|template|dist)$/.test(name);
  requireValue(!parts.some(part => ['.ssh', '.aws', '.kube', '.gnupg', '.docker', 'gcloud'].includes(part.toLowerCase())) &&
    (example || (!/(^|\.)env($|\.)/.test(name) &&
      !['.npmrc', '.pypirc', '.netrc', '.git-credentials', 'auth.json', 'credentials.json', '.credentials.json', 'application_default_credentials.json'].includes(name) &&
      !/\.(pem|key|p12|pfx)$/.test(name) && !/^id_(rsa|ed25519|ecdsa)$/.test(name))));
  for (const [index, part] of parts.entries()) {
    if (!forbidden.test(part)) continue;
    const isDirectory = index < parts.length - 1 || directory;
    if (index > 0 && isDirectory && /^(auth|home|hooks)$/.test(part)) continue;
    if (index > 0 && !isDirectory && /^auth(?:\.[A-Za-z0-9_-]+)*\.tsx?$/.test(part)) continue;
    fail();
  }
  return parts;
}
function owned(info) {
  requireValue(info.uid === BigInt(process.getuid()) && (info.mode & 0o7022n) === 0n);
}
async function rootHandle(path) {
  assertSupportedPlatform();
  requireValue(isAbsolute(path) && resolve(path) === path && path !== '/' &&
    await realpath(path) === path);
  // Ancestors need not be owned by this uid. Opening a directory without
  // enumerating it does not read its contents; NOATIME is reserved for data.
  const ancestorFlags = (FLAGS & ~constants.O_NOATIME) | constants.O_DIRECTORY;
  let handle = await open('/', ancestorFlags);
  try {
    for (const part of path.slice(1).split('/')) {
      const next = await open(`/proc/self/fd/${handle.fd}/${part}`, ancestorFlags);
      await handle.close(); handle = next;
    }
    const info = await handle.stat({ bigint: true }); owned(info); requireValue(info.isDirectory());
    return handle;
  } catch (error) { await handle.close(); throw error; }
}
async function unchanged(handle, before) {
  requireValue(identity(before) === identity(await handle.stat({ bigint: true })));
}
async function boundFile(directory, name, maxBytes) {
  const file = await open(`/proc/self/fd/${directory.fd}/${name}`, FLAGS);
  try { return await fileContents(file, maxBytes); } finally { await file.close(); }
}
async function fileContents(file, maxBytes) {
    const before = await file.stat({ bigint: true }); owned(before);
    requireValue(before.isFile() && before.nlink === 1n && before.size <= BigInt(maxBytes));
    const bytes = Buffer.alloc(Number(before.size) + 1); let used = 0;
    while (used < bytes.length) {
      const { bytesRead } = await file.read(bytes, used, Math.min(65536, bytes.length - used), used);
      if (!bytesRead) break;
      used += bytesRead;
    }
    requireValue(used === Number(before.size)); await unchanged(file, before);
    return { bytes: bytes.subarray(0, used), mode: Number(before.mode & 0o777n) };
}
async function verifyRoot(path, handle, before) {
  await unchanged(handle, before);
  const current = await rootHandle(path);
  try { requireValue(identity(before) === identity(await current.stat({ bigint: true }))); }
  finally { await current.close(); }
}
export async function readBoundFile(root, relative, { maxBytes = FILE_LIMIT } = {}) {
  assertSupportedPlatform();
  requireValue(Number.isSafeInteger(maxBytes) && maxBytes > 0 && maxBytes <= FILE_LIMIT);
  const parts = sourceParts(relative), handle = await rootHandle(root);
  const rootBefore = await handle.stat({ bigint: true }), parents = [], opened = [handle];
  let directory = handle;
  try {
    for (const part of parts.slice(0, -1)) {
      parents.push({ handle: directory, before: await directory.stat({ bigint: true }) });
      directory = await open(`/proc/self/fd/${directory.fd}/${part}`, FLAGS | constants.O_DIRECTORY);
      opened.push(directory);
      owned(await directory.stat({ bigint: true }));
    }
    parents.push({ handle: directory, before: await directory.stat({ bigint: true }) });
    const result = await boundFile(directory, parts.at(-1), maxBytes);
    for (const parent of parents) await unchanged(parent.handle, parent.before);
    await verifyRoot(root, handle, rootBefore);
    return result.bytes;
  } finally {
    for (const file of opened.reverse()) await file.close();
  }
}
export async function scanSourceTree(root, { omissions = [], maxFiles = 20000, maxTotalBytes = TOTAL_LIMIT, afterRead = async () => {} } = {}) {
  assertSupportedPlatform();
  requireValue(Number.isSafeInteger(maxFiles) && maxFiles > 0 && maxFiles <= 20000 &&
    Number.isSafeInteger(maxTotalBytes) && maxTotalBytes > 0 && maxTotalBytes <= TOTAL_LIMIT && typeof afterRead === 'function');
  const excluded = new Set(omissions), handle = await rootHandle(root);
  const rootBefore = await handle.stat({ bigint: true }), files = [], fingerprints = new Map(), verified = new Set();
  let total = 0, objects = 0;
  async function visit(directory, prefix, depth, verify = false) {
    requireValue(depth <= 32);
    const before = await directory.stat({ bigint: true }); owned(before);
    const names = (await readdir(`/proc/self/fd/${directory.fd}`)).sort();
    requireValue(names.length <= 40000);
    for (const name of names) {
      requireValue(++objects <= 40000);
      const path = prefix ? `${prefix}/${name}` : name;
      requireValue(!excluded.has(path));
      if (!prefix && name === '.git') {
        const git = await open(`/proc/self/fd/${directory.fd}/${name}`, FLAGS | constants.O_DIRECTORY);
        await git.close(); continue;
      }
      // The no-follow descriptor determines type before any contents are read.
      const entry = await open(`/proc/self/fd/${directory.fd}/${name}`, FLAGS);
      try {
        const info = await entry.stat({ bigint: true }); owned(info);
        sourceParts(path, info.isDirectory());
        if (info.isDirectory()) await visit(entry, path, depth + 1, verify);
        else {
          requireValue(info.isFile() && info.nlink === 1n);
          if (verify) {
            requireValue(fingerprints.get(path) === identity(info));
            verified.add(path); continue;
          }
          const file = await fileContents(entry, FILE_LIMIT);
          await unchanged(entry, info);
          fingerprints.set(path, identity(info));
          total += file.bytes.length;
          requireValue(total <= maxTotalBytes && files.length < maxFiles);
          files.push({ path, sha256: createHash('sha256').update(file.bytes).digest('hex'), mode: file.mode });
        }
      } finally { await entry.close(); }
    }
    requireValue(JSON.stringify(names) === JSON.stringify((await readdir(`/proc/self/fd/${directory.fd}`)).sort()));
    await unchanged(directory, before);
  }
  try {
    await visit(handle, '', 0);
    // Trusted reader callback only: keep the source descriptors/fingerprints
    // live across related artifact reads without hashing all source bytes twice.
    await afterRead();
    objects = 0; await visit(handle, '', 0, true); requireValue(fingerprints.size === verified.size);
    // All namespace enumeration finishes before the final leaf fingerprint
    // checks, including the last directory's closing readdir.
    for (const [path, expected] of fingerprints) {
      const parts = sourceParts(path), opened = []; let parent = handle;
      try {
        for (const part of parts.slice(0, -1)) {
          parent = await open(`/proc/self/fd/${parent.fd}/${part}`, FLAGS | constants.O_DIRECTORY);
          opened.push(parent); owned(await parent.stat({ bigint: true }));
        }
        const file = await open(`/proc/self/fd/${parent.fd}/${parts.at(-1)}`, FLAGS);
        try { requireValue(identity(await file.stat({ bigint: true })) === expected); }
        finally { await file.close(); }
      } finally { for (const parent of opened.reverse()) await parent.close(); }
    }
    await verifyRoot(root, handle, rootBefore);
    return files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  } finally { await handle.close(); }
}
