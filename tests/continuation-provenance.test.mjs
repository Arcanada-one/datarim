import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { validateProvenance, provenanceView, inspectWorkspace } from '../dev-tools/continuation-provenance.mjs';

// Fixtures must not be group- or world-writable: the reader refuses such entries by design
// (mode & 0o7022). A host umask of 0002 would otherwise fail these tests for the wrong reason.
process.umask(0o022);

const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' :
  value && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const hash = value => createHash('sha256').update(value).digest('hex');
const digest = (name, value) => hash(`continuation-${name}-v1\n` + canonical(value));
const pin = 'a'.repeat(64), id = '11111111-1111-4111-8111-111111111111';
function fixture() {
  const bootstrap = { childRunId: id, answerId: id, intentDigest: pin, frameworkCommit: 'b'.repeat(40), adapterVersion: 'ordinary-answer-v1',
    checkpoint: { checkpointId: id, manifestDigest: pin, sourceProfileDigest: pin, taskId: 'TASK-0001' } };
  const binding = { childRunId: id, answerId: id, intentDigest: pin, checkpointId: id, checkpointDigest: pin,
    sourceProfileDigest: pin, frameworkCommit: bootstrap.frameworkCommit, adapterVersion: bootstrap.adapterVersion, inputDigest: digest('bootstrap', bootstrap) };
  const files = ['main.ts', 'protected.ts'].map(path => ({ path, sha256: hash(path), mode: 0o600 }));
  const artifactIndex = [{ path: 'datarim/qa/evidence.json', sha256: hash('{}'), size: 2 }];
  const value = { ...binding, schemaVersion: 1, kind: 'controller-provenance', taskId: 'TASK-0001', attemptId: id,
    artifactIndex, artifactIndexDigest: digest('artifacts', artifactIndex), productionHold: true, approvalInheritance: 'none',
    source: { repository: 'app', scope: 'captured-repository-root', defaultClassification: 'reviewed-captured-source',
      snapshot: { fileCount: files.length, digest: hash(canonical(files)) },
      lineage: { originalRevision: 'c'.repeat(40), sanitizedRevision: 'd'.repeat(40), sourceProfileInputDigest: pin,
        baselineProvenanceInputDigest: pin, originalSanitizedInventoryDigest: pin, reviewedBaselineInventoryDigest: pin,
        baselineDigest: pin, parentManifestDigest: 'e'.repeat(64) },
      sensitiveFiles: [{ path: 'protected.ts', classification: 'sanitized-sensitive-source', originalSha256: pin, sanitizedSha256: pin,
        capturedSha256: hash('protected.ts'), capturedMode: 0o600, originalRegions: [{ start: 2, end: 4, sha256: pin }],
        protection: 'whole-file', equivalence: 'controller-reviewed-attestation' }],
      omissions: [{ path: 'omitted.txt', originalSha256: pin, reason: 'Controller-approved omission' }],
      allowedChanges: ['main.ts'], protectedPaths: ['protected.ts'] } };
  const control = { ...binding, schemaVersion: 2, taskId: value.taskId, attemptId: id,
    artifactIndexDigest: value.artifactIndexDigest, provenanceDigest: digest('provenance', value) };
  return { bootstrap, control, value };
}
function repin(data) {
  data.value.artifactIndexDigest = digest('artifacts', [...data.value.artifactIndex].sort((a,b) => a.path < b.path ? -1 : 1));
  data.control.artifactIndexDigest = data.value.artifactIndexDigest;
  data.control.provenanceDigest = digest('provenance', data.value);
}
test('complete provenance binds independent parent lineage and captured checkpoint', () => {
  const data = fixture();
  assert.equal(validateProvenance(data.value, data.bootstrap, data.control), data.value);
  const view = provenanceView(data.value);
  assert.equal(JSON.parse(view).provenance.source.lineage.parentManifestDigest, 'e'.repeat(64));
  assert.notEqual(data.value.source.lineage.parentManifestDigest, data.value.checkpointDigest);
});
test('recomputed digests cannot authorize malformed schema, coverage or ranges', () => {
  const mutations = [
    value => { value.source.unknown = true; },
    value => { value.source.protectedPaths = []; },
    value => { value.source.sensitiveFiles[0].originalRegions.push({ start: 3, end: 5, sha256: pin }); },
    value => { value.source.omissions[0].path = 'protected.ts/nested'; },
    value => { value.source.omissions[0].reason = '\ud800'; },
    value => { value.artifactIndex[0].path = '../escape'; },
    value => { value.source.lineage.originalRevision = pin; },
    value => { value.productionHold = false; },
  ];
  for (const mutate of mutations) {
    const data = fixture(); mutate(data.value); repin(data);
    assert.throws(() => validateProvenance(data.value, data.bootstrap, data.control));
  }
});
test('v1 execution and changed bindings fail closed', () => {
  for (const key of ['childRunId', 'answerId', 'inputDigest', 'checkpointDigest', 'attemptId']) {
    const data = fixture(); data.value[key] = key.endsWith('Digest') ? 'f'.repeat(64) : '22222222-2222-4222-8222-222222222222'; repin(data);
    assert.throws(() => validateProvenance(data.value, data.bootstrap, data.control));
  }
  const data = fixture(); data.control.schemaVersion = 1;
  assert.throws(() => validateProvenance(data.value, data.bootstrap, data.control));
});
test('provenance edited after the control pinned it fails closed', () => {
  // No repin: every field stays valid, only the control-bound digest disagrees.
  const data = fixture();
  data.value.source.omissions[0].reason = 'A different, equally well-formed reason';
  assert.throws(() => validateProvenance(data.value, data.bootstrap, data.control));
  const pinned = fixture(); pinned.control.provenanceDigest = 'f'.repeat(64);
  assert.throws(() => validateProvenance(pinned.value, pinned.bootstrap, pinned.control));
});
test('escaped expansion refuses the complete resource despite small raw bytes', () => {
  const data = fixture();
  data.value.source.omissions = Array.from({ length: 90 }, (_, index) => ({ path: `omitted-${index}.txt`, originalSha256: pin, reason: '<'.repeat(1024) }));
  repin(data); assert.ok(Buffer.byteLength(canonical(data.value)) < 262144);
  assert.throws(() => validateProvenance(data.value, data.bootstrap, data.control));
});
async function workspace(fn) {
  const root = await mkdtemp(join(tmpdir(), 'provenance-workspace-')), data = fixture();
  try {
    await mkdir(join(root, 'app')); await mkdir(join(root, 'datarim/qa'), { recursive: true });
    for (const file of ['main.ts', 'protected.ts']) await writeFile(join(root, 'app', file), file, { mode: 0o600 });
    await writeFile(join(root, 'datarim/qa/evidence.json'), '{}', { mode: 0o600 });
    await fn(root, data);
  } finally { await rm(root, { recursive: true, force: true }); }
}
test('current source modes and ordinary artifact edits are CHANGED, never renewed provenance', async () => workspace(async (root, data) => {
  assert.equal((await inspectWorkspace(data.value, root, { requireMatch: true })).state, 'MATCH');
  const before = provenanceView(data.value);
  await chmod(join(root, 'app/main.ts'), 0o644);
  assert.equal((await inspectWorkspace(data.value, root)).state, 'CHANGED');
  await assert.rejects(inspectWorkspace(data.value, root, { requireMatch: true }));
  await chmod(join(root, 'app/main.ts'), 0o600);
  await writeFile(join(root, 'datarim/qa/evidence.json'), '{"new":true}');
  assert.equal((await inspectWorkspace(data.value, root)).artifacts[0].state, 'CHANGED');
  assert.equal(provenanceView(data.value), before);
}));
test('new source outside capture delta is unverified; protected changes always refuse', async () => workspace(async (root, data) => {
  await writeFile(join(root, 'app/new.ts'), 'new source', { mode: 0o600 });
  assert.equal((await inspectWorkspace(data.value, root)).individualUnindexedFiles, 'fresh-unverified');
  await chmod(join(root, 'app/protected.ts'), 0o644);
  await assert.rejects(inspectWorkspace(data.value, root));
  await chmod(join(root, 'app/protected.ts'), 0o600);
  await writeFile(join(root, 'app/protected.ts'), 'changed source');
  await assert.rejects(inspectWorkspace(data.value, root));
}));
test('omissions and credential names refuse after entry while templates remain readable', async () => workspace(async (root, data) => {
  await writeFile(join(root, 'app/.env.example'), 'template', { mode: 0o600 });
  assert.equal((await inspectWorkspace(data.value, root)).state, 'CHANGED');
  for (const name of ['omitted.txt', '.env.production', 'credentials.json', 'private.key', '.pypirc']) {
    await writeFile(join(root, 'app', name), 'synthetic', { mode: 0o600 });
    await assert.rejects(inspectWorkspace(data.value, root));
    await rm(join(root, 'app', name));
  }
}));
