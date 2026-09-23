#!/usr/bin/env node
// Ordinary-answer ABI v1. PREPARED and served bytes are not model consumption,
// stage evidence, durable acknowledgement, or authorization to release HOLD.
import { constants } from 'node:fs';
import { open, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { validateProvenance, provenanceView, workspaceView } from './continuation-provenance.mjs';

const ROOT = '/worker/runtime';
const LIMIT = 65536;
const STAGES = ['prd', 'design', 'plan', 'do', 'qa', 'compliance'];
const BINDING = ['childRunId', 'answerId', 'intentDigest', 'checkpointId',
  'checkpointDigest', 'sourceProfileDigest', 'frameworkCommit', 'adapterVersion', 'inputDigest'];
const fail = category => { throw new Error(`continuation_${category}`); };
const requireValue = (condition, category = 'invalid') => { if (!condition) fail(category); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const canonical = v => Array.isArray(v) ? '[' + v.map(canonical).join(',') + ']' :
  v && typeof v === 'object' ? '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}' : JSON.stringify(v);
const digest = (domain, value) => hash(`continuation-${domain}-v1\n` + canonical(value));
const matches = (value, pattern) => typeof value === 'string' && pattern.test(value);
const uuid = value => requireValue(matches(value, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i));
const sha = value => requireValue(matches(value, /^[a-f0-9]{64}$/));
const identifier = value => requireValue(matches(value, /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$/));
const version = value => requireValue(Number.isInteger(value) && value > 0 && value <= 2147483647);
function shape(value, keys) {
  requireValue(value && Object.getPrototypeOf(value) === Object.prototype &&
    Object.keys(value).sort().join(',') === [...keys].sort().join(','), 'schema');
}
function unicode(value) {
  for (let i = 0; i < value.length; i++) {
    const n = value.charCodeAt(i);
    if (n >= 0xd800 && n <= 0xdbff) {
      const next = value.charCodeAt(++i);
      requireValue(next >= 0xdc00 && next <= 0xdfff, 'unicode');
    } else requireValue(n < 0xdc00 || n > 0xdfff, 'unicode');
  }
}
function tree(value, depth = 0) {
  requireValue(depth <= 12, 'depth');
  if (typeof value === 'string') { unicode(value); return; }
  if (value === null || typeof value === 'boolean') return;
  if (typeof value === 'number') { requireValue(Number.isSafeInteger(value), 'number'); return; }
  requireValue(value && typeof value === 'object', 'schema');
  requireValue(Array.isArray(value) || Object.getPrototypeOf(value) === Object.prototype, 'schema');
  for (const key of Object.keys(value)) {
    requireValue(!['__proto__', 'prototype', 'constructor'].includes(key), 'key');
    const property = Object.getOwnPropertyDescriptor(value, key);
    requireValue(property && 'value' in property, 'schema');
    unicode(key); tree(property.value, depth + 1);
  }
}
function prose(value) {
  requireValue(typeof value === 'string' && value.length >= 1 && value.length <= 8000 &&
    !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value), 'prose');
}
function time(value) {
  // Match shared datetime(): UTC, optional seconds, arbitrary fractional digits.
  // Parse only for validation/freshness; retain the original bytes in all digests.
  requireValue(matches(value, /^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d+)?)?Z$/), 'time');
  const n = Date.parse(value);
  const seconds = value[16] === ':' ? value.slice(0, 19) : value.slice(0, 16) + ':00';
  requireValue(Number.isFinite(n) && new Date(n).toISOString().slice(0, 19) === seconds, 'time');
  return n;
}
function hold(value) {
  requireValue(value.productionHold === true && value.approvalInheritance === 'none', 'hold');
}
function validateQuestion(q, response) {
  shape(q, ['id', 'runId', 'requestKey', 'stage', 'spec', 'expiresAt']);
  uuid(q.id); uuid(q.runId); identifier(q.requestKey); identifier(q.stage);
  // Original undecided questions may already be expired. Preserve their exact
  // timestamp/context; the newly issued checkpoint supplies continuation TTL.
  time(q.expiresAt);
  const s = q.spec;
  requireValue(s && response && ['text', 'choice'].includes(s.kind) && response.kind === s.kind, 'ordinary');
  prose(s.prompt);
  if (s.kind === 'text') {
    shape(s, ['kind', 'prompt', 'maxLength']); shape(response, ['kind', 'text']);
    requireValue(Number.isInteger(s.maxLength) && s.maxLength >= 1 && s.maxLength <= 8000);
    prose(response.text); requireValue(response.text.length <= s.maxLength, 'answer');
  } else {
    shape(s, ['kind', 'prompt', 'options']); shape(response, ['kind', 'optionId']);
    identifier(response.optionId);
    requireValue(Array.isArray(s.options) && s.options.length >= 2 && s.options.length <= 20);
    for (const o of s.options) { shape(o, ['id', 'label']); identifier(o.id); prose(o.label); }
    requireValue(new Set(s.options.map(o => o.id)).size === s.options.length &&
      s.options.some(o => o.id === response.optionId), 'answer');
  }
}
function validateBootstrap(b, now, fresh = true) {
  shape(b, ['schemaVersion', 'childRunId', 'answerId', 'intentDigest', 'checkpoint',
    'response', 'answerDigest', 'frameworkCommit', 'adapterVersion', 'productionHold', 'approvalInheritance']);
  requireValue(b.schemaVersion === 1 && b.adapterVersion === 'ordinary-answer-v1');
  uuid(b.childRunId); uuid(b.answerId); sha(b.intentDigest); sha(b.answerDigest);
  requireValue(matches(b.frameworkCommit, /^[a-f0-9]{40}$/)); hold(b);
  const c = b.checkpoint;
  shape(c, ['schemaVersion', 'parentVersion', 'questionId', 'questionVersion', 'questionContextDigest',
    'checkpointId', 'parentRunId', 'taskId', 'asanaGid', 'question', 'sourceProfileDigest',
    'manifestDigest', 'createdAt', 'expiresAt', 'productionHold', 'approvalInheritance']);
  requireValue(c.schemaVersion === 1); hold(c);
  version(c.parentVersion); version(c.questionVersion);
  uuid(c.questionId); uuid(c.checkpointId); uuid(c.parentRunId);
  sha(c.questionContextDigest); sha(c.sourceProfileDigest); sha(c.manifestDigest);
  requireValue(matches(c.taskId, /^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$/) && matches(c.asanaGid, /^[0-9]{1,32}$/));
  const created = time(c.createdAt), expires = time(c.expiresAt);
  requireValue(created <= now && (!fresh || expires > now) && expires > created && expires - created <= 900000, 'expired');
  validateQuestion(c.question, b.response);
  requireValue(b.childRunId !== c.parentRunId && c.question.id === c.questionId &&
    c.question.runId === c.parentRunId && hash(canonical(c.question)) === c.questionContextDigest &&
    digest('answer', b.response) === b.answerDigest, 'identity');
}
function validateBinding(binding, b) {
  shape(binding, BINDING);
  const expected = { childRunId: b.childRunId, answerId: b.answerId, intentDigest: b.intentDigest,
    checkpointId: b.checkpoint.checkpointId, checkpointDigest: b.checkpoint.manifestDigest,
    sourceProfileDigest: b.checkpoint.sourceProfileDigest, frameworkCommit: b.frameworkCommit,
    adapterVersion: b.adapterVersion, inputDigest: digest('bootstrap', b) };
  requireValue(BINDING.every(k => binding[k] === expected[k]), 'binding');
}
function validateControl(c, b) {
  shape(c, [...BINDING, 'schemaVersion', 'taskId', 'attemptId', 'route', 'routeDigest',
    'artifactIndexDigest', 'provenanceDigest', 'resumeStage', 'presentationNonce', 'productionHold', 'approvalInheritance']);
  validateBinding(Object.fromEntries(BINDING.map(k => [k, c[k]])), b);
  requireValue(c.schemaVersion === 2 && c.taskId === b.checkpoint.taskId, 'binding');
  uuid(c.attemptId); sha(c.artifactIndexDigest); sha(c.provenanceDigest); sha(c.routeDigest); hold(c);
  requireValue(matches(c.presentationNonce, /^[a-f0-9]{32}$/), 'nonce');
  requireValue(Array.isArray(c.route) && c.route.length >= 1 && c.route.length <= STAGES.length &&
    c.route.every((s, i) => STAGES.includes(s) && (i === 0 || STAGES.indexOf(s) > STAGES.indexOf(c.route[i - 1]))) &&
    c.route.includes(c.resumeStage) && digest('route', c.route) === c.routeDigest, 'route');
  // Equality is a consistency check only. The independently supplied control
  // selects the stage; question.stage can never create missing route authority.
  requireValue(c.resumeStage === b.checkpoint.question.stage, 'stage');
}
function escapeString(value) {
  let result = '"';
  for (let i = 0; i < value.length; i++) {
    const c = value[i];
    result += /[A-Za-z0-9 .,_-]/.test(c) ? c : '\\u' + value.charCodeAt(i).toString(16).padStart(4, '0');
  }
  return result + '"';
}
function escaped(value) {
  if (typeof value === 'string') return escapeString(value);
  if (Array.isArray(value)) return '[' + value.map(escaped).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => escapeString(k) + ':' + escaped(value[k])).join(',') + '}';
  return JSON.stringify(value);
}

/** Pure admission check. Caller MUST authenticate control provenance separately.
 * A valid digest, a renderer return, or PREPARED cannot establish that custody. */
export function renderContinuationModelView({ bootstrap, control }) {
  tree(bootstrap); tree(control);
  requireValue(Buffer.byteLength(canonical(bootstrap)) <= LIMIT && Buffer.byteLength(canonical(control)) <= LIMIT, 'size');
  validateBootstrap(bootstrap, Date.now()); validateControl(control, bootstrap);
  const view = escaped({ kind: 'ordinary-answer-data', control, bootstrap }) + '\n';
  requireValue(Buffer.byteLength(view) <= LIMIT, 'view_size');
  return view;
}

function parse(bytes, limit = LIMIT) {
  requireValue(bytes.length <= limit && !(bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf), 'encoding');
  let text, value;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); value = JSON.parse(text); }
  catch { fail('encoding'); }
  tree(value);
  // Canonical wire form rejects duplicate keys, ignored whitespace and JSON
  // number/escape ambiguities before any digest or model-view interpretation.
  requireValue(canonical(value) === text, 'canonical');
  return value;
}
async function readResource(root, name, limit = LIMIT) {
  const file = await open(`/proc/self/fd/${root.fd}/${name}`, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await file.stat({ bigint: true });
    requireValue(before.isFile() && before.nlink === 1n && (before.mode & 0o777n) === 0o400n && before.size <= BigInt(limit), 'custody');
    const buffer = Buffer.alloc(limit + 1);
    let size = 0, count;
    do { ({ bytesRead: count } = await file.read(buffer, size, buffer.length - size, null)); size += count; }
    while (count > 0 && size < buffer.length);
    const after = await file.stat({ bigint: true });
    requireValue(size === Number(before.size) && size <= limit &&
      ['dev', 'ino', 'mode', 'nlink', 'size', 'mtimeNs', 'ctimeNs'].every(k => before[k] === after[k]), 'custody');
    return parse(buffer.subarray(0, size), limit);
  } finally { await file.close(); }
}
async function resources() {
  try {
    requireValue(await realpath(ROOT) === ROOT, 'custody');
    const root = await open(ROOT, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try {
      const before = await root.stat({ bigint: true });
      const data = { bootstrap: await readResource(root, 'continuation.json'), control: await readResource(root, 'continuation-control.json'),
        provenance: await readResource(root, 'continuation-provenance.json', 262144) };
      const current = await open(ROOT, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
      try {
        const after = await current.stat({ bigint: true });
        requireValue(['dev', 'ino', 'mode', 'mtimeNs', 'ctimeNs'].every(key => before[key] === after[key]), 'custody');
      } finally { await current.close(); }
      return data;
    } finally { await root.close(); }
  } catch { fail('resource_unavailable'); }
}
export async function readContinuationModelView() {
  const data = await resources();
  const view = renderContinuationModelView(data);
  validateProvenance(data.provenance, data.bootstrap, data.control);
  return view;
}
export async function readContinuationProvenanceView(workspaceStatus = false) {
  const data = await resources();
  tree(data.bootstrap); tree(data.control);
  validateBootstrap(data.bootstrap, Date.now(), false); validateControl(data.control, data.bootstrap);
  const verified = validateProvenance(data.provenance, data.bootstrap, data.control);
  if (!workspaceStatus) return provenanceView(verified);
  return workspaceView(verified);
}
export async function prepareContinuation(input) {
  shape(input, ['bootstrap', 'binding']); tree(input);
  const data = await resources();
  renderContinuationModelView(data);
  requireValue(canonical(input.bootstrap) === canonical(data.bootstrap), 'binding');
  validateBinding(input.binding, data.bootstrap);
  await workspaceView(validateProvenance(data.provenance, data.bootstrap, data.control), true);
  const { childRunId, answerId, checkpointId, inputDigest } = input.binding;
  return { kind: 'ordinary-answer-prepared', childRunId, answerId, checkpointId, inputDigest, productionHold: true };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    requireValue(process.argv.length === 3 && ['--model-view', '--provenance-view', '--workspace-status'].includes(process.argv[2]), 'arguments');
    process.stdout.write(process.argv[2] === '--model-view' ? await readContinuationModelView() :
      await readContinuationProvenanceView(process.argv[2] === '--workspace-status'));
  } catch { process.stderr.write('continuation_unavailable\n'); process.exitCode = 1; }
}
