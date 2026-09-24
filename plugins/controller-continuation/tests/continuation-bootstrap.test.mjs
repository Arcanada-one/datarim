import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, link, rm, symlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderContinuationModelView, readContinuationModelView, readContinuationProvenanceView,
  prepareContinuation, parseArguments, UNSUPPORTED_PLATFORM } from '../dev-tools/continuation-bootstrap.mjs';
import { LINUX, buildResources, rebind, materialize, canonical, hash, RESTART } from './fixtures.mjs';

const run = promisify(execFile);
const CLI = fileURLToPath(new URL('../dev-tools/continuation-bootstrap.mjs', import.meta.url));
const linuxOnly = { skip: LINUX ? false : 'descriptor-anchored reads exist only on Linux; the refusal is asserted separately' };
const view = data => renderContinuationModelView({ bootstrap: data.bootstrap, control: data.control });
const refuses = (data, category) => assert.throws(() => view(data), { message: `continuation_${category}` });
async function withFixture(data, fn, options) {
  const fixture = await materialize(data, options);
  try { await fn(fixture); } finally { await fixture.cleanup(); }
}

// ---------------------------------------------------------------------------
// Pure admission checks: identical on every platform.

test('a complete v2 resource renders an escaped, untrusted data view', () => {
  const data = buildResources();
  const output = view(data);
  assert.ok(output.endsWith('\n'));
  // Markup and quotes in the answer reach the model only as \u escapes.
  assert.ok(!output.includes('<') && !output.includes('>'));
  assert.ok(output.includes('\\u003csystem\\u003e') && output.includes('\\u0022quoted\\u0022'));
  const parsed = JSON.parse(output);
  assert.equal(parsed.kind, 'ordinary-answer-data');
  assert.equal(parsed.bootstrap.response.text, data.bootstrap.response.text);
  assert.equal(parsed.control.resumeStage, 'qa');
});

test('trackerRef is tracker-agnostic: null or an opaque bounded reference', () => {
  for (const trackerRef of [null, 'jira:ABC-123', 'github:org/repo#42', '12345']) {
    assert.doesNotThrow(() => view(rebind(buildResources({ trackerRef }))), String(trackerRef));
  }
  for (const trackerRef of [42, '', '-leading', 'has space', '../x'.padEnd(300, 'x'), 'a\u0000b']) {
    refuses(rebind(buildResources({ trackerRef })), 'tracker');
  }
  const legacy = buildResources();
  legacy.bootstrap.checkpoint.legacyTrackerId = '1'; // a vendor-specific id field is not part of the schema
  delete legacy.bootstrap.checkpoint.trackerRef;
  refuses(rebind(legacy), 'schema');
});

test('hold, freshness, answer and binding guards refuse a re-bound fixture', () => {
  const cases = [
    ['hold', data => { data.bootstrap.checkpoint.productionHold = false; }],
    ['hold', data => { data.control.approvalInheritance = 'inherited'; }],
    ['expired', data => { data.bootstrap.checkpoint.expiresAt = new Date(Date.now() - 1000).toISOString(); }],
    // Admission TTL is bounded at 15 minutes after checkpoint creation.
    ['expired', data => { data.bootstrap.checkpoint.expiresAt = new Date(Date.now() + 16 * 60000).toISOString(); }],
    ['answer', data => { data.bootstrap.response.text = 'x'.repeat(201); }],
    ['stage', data => { data.control.resumeStage = 'compliance'; }],
    ['route', data => { data.control.route = ['compliance', 'qa']; }],
  ];
  for (const [category, mutate] of cases) {
    const data = buildResources(); mutate(data); rebind(data);
    refuses(data, category);
  }
  const unbound = buildResources(); unbound.bootstrap.response.text = 'A different answer';
  refuses(unbound, 'identity');
  const foreign = buildResources(); foreign.control.inputDigest = 'f'.repeat(64);
  refuses(foreign, 'binding');
});

test('control v3 stage restart admits only the superseding-source QA-to-DO shape', () => {
  assert.equal(JSON.parse(view(buildResources({ restart: true }))).control.resumeStage, 'do');
  const cases = [
    data => { data.control.stageRestart.kind = 'any-restart'; },
    data => { data.control.stageRestart.questionStage = 'do'; },
    data => { data.control.resumeStage = 'qa'; },
    data => { data.control.route = ['do', 'qa']; },
    data => { data.control.route = ['plan', 'do', 'qa', 'compliance']; },
    data => { data.control.stageRestart.evidencePath = data.control.stageRestart.acceptancePath; },
    data => { data.control.stageRestart.attestationPath = 'elsewhere/attestation.json'; },
    data => { data.control.stageRestart.acceptancePath = 'datarim/../acceptance.json'; },
    data => { data.control.stageRestart.candidateRevision = 'e'.repeat(39); },
  ];
  for (const mutate of cases) {
    const data = buildResources({ restart: true }); mutate(data); rebind(data);
    refuses(data, 'stage_restart');
  }
  // A v3 restart must come from a QA question; a DO question cannot claim it.
  const doQuestion = buildResources({ restart: true });
  doQuestion.bootstrap.checkpoint.question.stage = 'do'; rebind(doQuestion);
  refuses(doQuestion, 'stage_restart');
  // v2 carries no restart authority at all.
  const v2 = buildResources({ restart: true }); v2.control.schemaVersion = 2; rebind(v2);
  refuses(v2, 'schema');
});

test('arguments accept only a mode plus explicit absolute roots, each at most once', () => {
  assert.deepEqual(parseArguments(['--model-view']), { mode: '--model-view', options: {} });
  assert.deepEqual(parseArguments(['--workspace-status', '--runtime-root=/srv/rt', '--workspace-root=/srv/ws']),
    { mode: '--workspace-status', options: { runtimeRoot: '/srv/rt', workspaceRoot: '/srv/ws' } });
  for (const argv of [[], ['--resume'], ['--model-view', '--runtime-root=relative'], ['--model-view', '--runtime-root=/'],
    ['--model-view', '--runtime-root=/a/../b'], ['--model-view', '--runtime-root=/a', '--runtime-root=/b'],
    ['--model-view', '--root=/a'], ['--model-view', '--runtime-root', '/a']]) {
    assert.throws(() => parseArguments(argv), { message: 'continuation_arguments' }, argv.join(' '));
  }
});

// ---------------------------------------------------------------------------
// Platform contract: the same valid fixture succeeds on Linux and is refused,
// with the exact category, everywhere else. A blanket rejection cannot pass both.

test('entry points serve a valid fixture on Linux and refuse it with the exact category elsewhere', async () => {
  for (const restart of [false, true]) await withFixture(buildResources({ restart }), async ({ runtimeRoot, workspaceRoot }) => {
    const roots = { runtimeRoot, workspaceRoot };
    const input = { bootstrap: buildResources({ restart }).bootstrap, binding: null };
    const calls = [() => readContinuationModelView(roots), () => readContinuationProvenanceView(roots),
      () => readContinuationProvenanceView({ ...roots, workspaceStatus: true })];
    if (!LINUX) {
      for (const call of [...calls, () => prepareContinuation(input, roots)]) {
        await assert.rejects(call(), { message: UNSUPPORTED_PLATFORM });
      }
      return;
    }
    const [model, provenance, status] = await Promise.all(calls.map(call => call()));
    assert.equal(JSON.parse(model).kind, 'ordinary-answer-data');
    assert.equal(JSON.parse(provenance).kind, 'controller-provenance-data');
    assert.equal(JSON.parse(status).state, 'MATCH');
  });
});

test('the CLI refuses non-Linux with exit 3 and empty stdout; on Linux it serves explicit roots', async () => {
  await withFixture(buildResources(), async ({ runtimeRoot, workspaceRoot }) => {
    const args = [CLI, '--workspace-status', `--runtime-root=${runtimeRoot}`, `--workspace-root=${workspaceRoot}`];
    if (!LINUX) {
      for (const argv of [args, [CLI, '--model-view'], [CLI, '--not-a-mode']]) {
        const error = await run(process.execPath, argv).then(() => null, failure => failure);
        assert.ok(error, 'must not exit 0');
        assert.equal(error.code, 3);
        assert.equal(error.stdout, '');
        assert.equal(error.stderr, `${UNSUPPORTED_PLATFORM}\n`);
      }
      return;
    }
    const { stdout } = await run(process.execPath, args);
    assert.equal(JSON.parse(stdout).state, 'MATCH');
    for (const argv of [[CLI, '--not-a-mode'], [CLI, '--model-view', '--runtime-root=relative']]) {
      const error = await run(process.execPath, argv).then(() => null, failure => failure);
      assert.equal(error.code, 1); assert.equal(error.stdout, ''); assert.equal(error.stderr, 'continuation_unavailable\n');
    }
  });
});

// ---------------------------------------------------------------------------
// Linux custody and restart-artifact checks. Every refusal below is paired with
// the success of the same unmodified fixture in the test above.

test('runtime root custody: writable roots, loose modes, links and non-canonical bytes are refused', linuxOnly, async () => {
  const unavailable = { message: 'continuation_resource_unavailable' };
  await withFixture(buildResources(), async ({ runtimeRoot, workspaceRoot }) => {
    await assert.rejects(readContinuationModelView({ runtimeRoot, workspaceRoot }), unavailable);
  }, { runtimeMode: 0o755 });
  await withFixture(buildResources(), async ({ runtimeRoot, workspaceRoot }) => {
    await assert.rejects(readContinuationModelView({ runtimeRoot, workspaceRoot }), unavailable);
  }, { resourceMode: 0o600 });
  for (const damage of ['symlink', 'hardlink', 'pretty']) {
    await withFixture(buildResources(), async ({ runtimeRoot, workspaceRoot, base }) => {
      await chmod(runtimeRoot, 0o755);
      const target = join(runtimeRoot, 'continuation.json');
      const bytes = canonical(buildResources().bootstrap);
      if (damage === 'symlink') {
        await writeFile(join(base, 'elsewhere.json'), bytes, { mode: 0o400 });
        await rm(target); await symlink(join(base, 'elsewhere.json'), target);
      } else if (damage === 'hardlink') {
        await link(target, join(base, 'second-name.json'));
      } else {
        await rm(target); await writeFile(target, JSON.stringify(JSON.parse(bytes), null, 2), { mode: 0o400 });
      }
      await chmod(runtimeRoot, 0o555);
      await assert.rejects(readContinuationModelView({ runtimeRoot, workspaceRoot }), unavailable, damage);
    });
  }
});

test('prepare requires workspace MATCH and the exact bound bootstrap', linuxOnly, async () => {
  const data = buildResources();
  await withFixture(data, async ({ runtimeRoot, workspaceRoot }) => {
    const roots = { runtimeRoot, workspaceRoot };
    const binding = Object.fromEntries(['childRunId', 'answerId', 'intentDigest', 'checkpointId', 'checkpointDigest',
      'sourceProfileDigest', 'frameworkCommit', 'adapterVersion', 'inputDigest'].map(key => [key, data.control[key]]));
    const prepared = await prepareContinuation({ bootstrap: data.bootstrap, binding }, roots);
    assert.equal(prepared.kind, 'ordinary-answer-prepared');
    assert.equal(prepared.productionHold, true);
    const other = buildResources(); other.bootstrap.response.text = 'Another answer'; rebind(other);
    await assert.rejects(prepareContinuation({ bootstrap: other.bootstrap, binding }, roots), { message: 'continuation_binding' });
    await writeFile(join(workspaceRoot, 'app', 'main.ts'), 'export const main = 2;\n');
    await assert.rejects(prepareContinuation({ bootstrap: data.bootstrap, binding }, roots));
  });
});

/** Replace one workspace artifact and optionally re-pin the controller index. */
function withArtifact(path, text, { repin }) {
  const data = buildResources({ restart: true });
  data.workspaceFiles[path] = text;
  if (repin) {
    const entry = data.provenance.artifactIndex.find(item => item.path === path);
    entry.sha256 = hash(text); entry.size = Buffer.byteLength(text);
    if (path === RESTART.acceptance) data.control.stageRestart.acceptanceSha256 = hash(text);
  }
  return rebind(data);
}
const attestation = changes => canonical({ ...JSON.parse(buildResources({ restart: true }).workspaceFiles[RESTART.attestation]), ...changes });

test('superseding-source restart re-verifies its attestation and acceptance bytes from the workspace', linuxOnly, async () => {
  const cases = [
    // Workspace bytes changed after the controller indexed them.
    [withArtifact(RESTART.attestation, attestation({ reviewDigest: '9'.repeat(64) }), { repin: false }), 'stage_restart_artifacts'],
    [withArtifact(RESTART.acceptance, '{"cases":[1]}', { repin: false }), 'stage_restart_artifacts'],
    // Consistently indexed, but the attestation itself does not authorise a restart.
    [withArtifact(RESTART.attestation, attestation({ taskCompletionEvidence: true }), { repin: true }), 'stage_restart_attestation'],
    [withArtifact(RESTART.attestation, attestation({ classification: 'self-asserted' }), { repin: true }), 'stage_restart_attestation'],
    [withArtifact(RESTART.attestation, attestation({ parent: { runId: '88888888-8888-4888-8888-888888888888' } }), { repin: true }), 'stage_restart_attestation'],
  ];
  const lineage = buildResources({ restart: true });
  lineage.provenance.source.lineage.sanitizedRevision = '3'.repeat(40); rebind(lineage);
  cases.push([lineage, 'stage_restart_attestation']);
  const unindexed = buildResources({ restart: true });
  unindexed.provenance.artifactIndex = unindexed.provenance.artifactIndex.filter(item => item.path !== RESTART.evidence);
  delete unindexed.workspaceFiles[RESTART.evidence]; rebind(unindexed);
  cases.push([unindexed, 'stage_restart_index']);
  for (const [data, category] of cases) {
    await withFixture(data, async ({ runtimeRoot, workspaceRoot }) => {
      await assert.rejects(readContinuationModelView({ runtimeRoot, workspaceRoot }), { message: `continuation_${category}` }, category);
    });
  }
});

test('the workspace root is an explicit argument: a different root is read, not the default', linuxOnly, async () => {
  await withFixture(buildResources({ restart: true }), async ({ runtimeRoot, workspaceRoot, base }) => {
    await assert.rejects(readContinuationModelView({ runtimeRoot, workspaceRoot: join(base, 'missing') }),
      { code: 'ENOENT' });
    assert.equal(JSON.parse(await readContinuationModelView({ runtimeRoot, workspaceRoot })).control.resumeStage, 'do');
  });
});
