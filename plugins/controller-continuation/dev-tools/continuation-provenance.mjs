// Independent framework consumer of the immutable controller provenance ABI.
import { createHash } from 'node:crypto';
import { readBoundFile, scanSourceTree, sourceParts, assertSupportedPlatform, DEFAULT_WORKSPACE_ROOT } from './continuation-provenance-fs.mjs';

const LIMIT = 262144;
const BINDING = ['childRunId', 'answerId', 'intentDigest', 'checkpointId', 'checkpointDigest',
  'sourceProfileDigest', 'frameworkCommit', 'adapterVersion', 'inputDigest'];
const fail = () => { throw new Error('continuation_provenance_unavailable'); };
const must = value => { if (!value) fail(); };
const hash = value => createHash('sha256').update(value).digest('hex');
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' :
  value && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const domain = (name, value) => hash(`continuation-${name}-v1\n` + canonical(value));
const sha = value => must(typeof value === 'string' && /^[a-f0-9]{64}$/.test(value));
const shape = (value, names) => must(value && Object.getPrototypeOf(value) === Object.prototype &&
  Object.keys(value).sort().join(',') === [...names].sort().join(','));
const list = (value, min = 0, max = 20000) => must(Array.isArray(value) && value.length >= min && value.length <= max);
const integer = (value, min, max = Number.MAX_SAFE_INTEGER) => must(Number.isSafeInteger(value) && value >= min && value <= max);
function tree(value, depth = 0) {
  must(depth <= 12);
  if (typeof value === 'string') { must(!/[\ud800-\udfff]/u.test(value)); return; }
  if (value === null || typeof value === 'boolean') return;
  if (typeof value === 'number') { integer(value, 0); return; }
  must(value && typeof value === 'object' && (Array.isArray(value) || Object.getPrototypeOf(value) === Object.prototype));
  for (const key of Object.keys(value)) {
    must(!['__proto__', 'prototype', 'constructor'].includes(key));
    const property = Object.getOwnPropertyDescriptor(value, key);
    must(property && 'value' in property); tree(key, depth + 1); tree(property.value, depth + 1);
  }
}
function path(value) {
  must(typeof value === 'string' && Buffer.byteLength(value) <= 1024 && !/[\x00-\x1f\x7f\\]/.test(value));
  const parts = value.split('/');
  must(parts.length <= 32 && parts.every(part => part && part !== '.' && part !== '..' && Buffer.byteLength(part) <= 255));
}
function paths(value) { list(value); value.forEach(path); must(new Set(value).size === value.length); }
const sorted = values => [...values].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
function escaped(value) {
  if (typeof value === 'string') return '"' + value.replace(/[^A-Za-z0-9 .,_-]/g,
    character => `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}`) + '"';
  if (Array.isArray(value)) return '[' + value.map(escaped).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => escaped(key) + ':' + escaped(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
function boundedView(value) { const view = escaped(value) + '\n'; must(Buffer.byteLength(view) <= LIMIT); return view; }

/** Consistency checks only. The fixed reader must authenticate resource custody
 * and validate the ordinary bootstrap/control before calling this function. */
export function validateProvenance(value, bootstrap, control) {
  tree(value); must(Buffer.byteLength(canonical(value)) <= LIMIT);
  shape(value, [...BINDING, 'schemaVersion', 'kind', 'taskId', 'attemptId', 'artifactIndex',
    'artifactIndexDigest', 'source', 'productionHold', 'approvalInheritance']);
  must(value.schemaVersion === 1 && value.kind === 'controller-provenance' && [2,3].includes(control.schemaVersion) &&
    value.productionHold === true && value.approvalInheritance === 'none');
  const expected = { childRunId: bootstrap.childRunId, answerId: bootstrap.answerId, intentDigest: bootstrap.intentDigest,
    checkpointId: bootstrap.checkpoint.checkpointId, checkpointDigest: bootstrap.checkpoint.manifestDigest,
    sourceProfileDigest: bootstrap.checkpoint.sourceProfileDigest, frameworkCommit: bootstrap.frameworkCommit,
    adapterVersion: bootstrap.adapterVersion, inputDigest: domain('bootstrap', bootstrap) };
  must(BINDING.every(key => value[key] === expected[key] && value[key] === control[key]) &&
    value.taskId === control.taskId && value.taskId === bootstrap.checkpoint.taskId && value.attemptId === control.attemptId);
  sha(value.artifactIndexDigest); sha(control.provenanceDigest);
  list(value.artifactIndex, 1);
  for (const item of value.artifactIndex) {
    shape(item, ['path', 'sha256', 'size']); path(item.path); sourceParts(item.path);
    must(item.path.startsWith('datarim/') && /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(item.path));
    sha(item.sha256); integer(item.size, 0, 8 * 1024 * 1024);
  }
  must(new Set(value.artifactIndex.map(item => item.path)).size === value.artifactIndex.length &&
    domain('artifacts', sorted(value.artifactIndex)) === value.artifactIndexDigest && value.artifactIndexDigest === control.artifactIndexDigest);
  const source = value.source;
  shape(source, ['repository', 'scope', 'defaultClassification', 'snapshot', 'lineage', 'sensitiveFiles', 'omissions', 'allowedChanges', 'protectedPaths']);
  must(typeof source.repository === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(source.repository) &&
    source.scope === 'captured-repository-root' && source.defaultClassification === 'reviewed-captured-source');
  sourceParts(source.repository, true);
  shape(source.snapshot, ['fileCount', 'digest']); integer(source.snapshot.fileCount, 1, 20000); sha(source.snapshot.digest);
  shape(source.lineage, ['originalRevision', 'sanitizedRevision', 'sourceProfileInputDigest', 'baselineProvenanceInputDigest',
    'originalSanitizedInventoryDigest', 'reviewedBaselineInventoryDigest', 'baselineDigest', 'parentManifestDigest']);
  for (const [key, item] of Object.entries(source.lineage)) {
    if (key.endsWith('Revision')) must(typeof item === 'string' && /^[a-f0-9]{40}$/.test(item)); else sha(item);
  }
  paths(source.allowedChanges); paths(source.protectedPaths); list(source.sensitiveFiles); list(source.omissions);
  const sensitivePaths = [];
  for (const item of source.sensitiveFiles) {
    shape(item, ['path', 'classification', 'originalSha256', 'sanitizedSha256', 'capturedSha256', 'capturedMode', 'originalRegions', 'protection', 'equivalence']);
    path(item.path); sourceParts(item.path); sensitivePaths.push(item.path);
    must(item.classification === 'sanitized-sensitive-source' && item.protection === 'whole-file' && item.equivalence === 'controller-reviewed-attestation');
    [item.originalSha256, item.sanitizedSha256, item.capturedSha256].forEach(sha);
    must([0o600, 0o700].includes(item.capturedMode));
    list(item.originalRegions, 1, 256); let end = 0;
    for (const region of item.originalRegions) {
      shape(region, ['start', 'end', 'sha256']); integer(region.start, end); integer(region.end, region.start + 1); sha(region.sha256); end = region.end;
    }
  }
  must(new Set(sensitivePaths).size === sensitivePaths.length && sensitivePaths.length === source.protectedPaths.length &&
    sensitivePaths.every(item => source.protectedPaths.includes(item)));
  const omitted = [];
  for (const item of source.omissions) {
    shape(item, ['path', 'originalSha256', 'reason']); path(item.path); sha(item.originalSha256); omitted.push(item.path);
    must(typeof item.reason === 'string' && item.reason.length >= 1 && item.reason.length <= 1024);
    must(![...sensitivePaths, ...source.allowedChanges, ...source.protectedPaths].some(other =>
      other === item.path || other.startsWith(item.path + '/') || item.path.startsWith(other + '/')));
  }
  must(new Set(omitted).size === omitted.length && domain('provenance', value) === control.provenanceDigest);
  provenanceView(value); // Escaped-model-view overflow refuses the entire resource.
  return value;
}
export function provenanceView(value) {
  return boundedView({ kind: 'controller-provenance-data', provenance: value });
}
/** Filesystem result is current comparison, never a new attestation. */
export async function inspectWorkspace(value, workspaceRoot, { requireMatch = false } = {}) {
  assertSupportedPlatform();
  const source = value.source, root = `${workspaceRoot}/${source.repository}`;
  let matches = true;
  const artifacts = [], observations = new Map(); let artifactBytes = 0;
  const readArtifacts = async () => { for (const item of value.artifactIndex) {
    let actual;
    try { actual = await readBoundFile(workspaceRoot, item.path); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    artifactBytes += actual?.length ?? 0; must(artifactBytes <= 128 * 1024 * 1024);
    observations.set(item.path, actual === undefined ? null : hash(actual));
    const match = actual !== undefined && actual.length === item.size && hash(actual) === item.sha256;
    matches &&= match; artifacts.push({ path: item.path, state: match ? 'MATCH' : 'CHANGED' });
  } };
  const files = await scanSourceTree(root, { omissions: source.omissions.map(item => item.path), afterRead: readArtifacts });
  const byPath = new Map(files.map(item => [item.path, item]));
  for (const item of source.sensitiveFiles) must(byPath.get(item.path)?.sha256 === item.capturedSha256 && byPath.get(item.path)?.mode === item.capturedMode);
  matches &&= files.length === source.snapshot.fileCount && hash(canonical(files)) === source.snapshot.digest;
  for (const [path, before] of observations) {
    let actual;
    try { actual = await readBoundFile(workspaceRoot, path); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    must((actual === undefined ? null : hash(actual)) === before);
  }
  if (requireMatch) must(matches);
  return { kind: 'controller-workspace-comparison', state: matches ? 'MATCH' : 'CHANGED',
    sourceSnapshot: { fileCount: files.length, digest: hash(canonical(files)) }, artifacts,
    individualUnindexedFiles: 'fresh-unverified', productionHold: true, approvalInheritance: 'none' };
}
export async function workspaceView(value, requireMatch = false, workspaceRoot = DEFAULT_WORKSPACE_ROOT) {
  return boundedView(await inspectWorkspace(value, workspaceRoot, { requireMatch }));
}
