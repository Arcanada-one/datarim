import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, chmod, symlink, link, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readBoundFile, scanSourceTree } from '../dev-tools/continuation-provenance-fs.mjs';

async function fixture(fn) {
  const root = await mkdtemp(join(tmpdir(), 'provenance-fs-'));
  try { await fn(root); } finally { await rm(root, { recursive: true, force: true }); }
}
test('bound reads reject links, traversal and special namespaces', async () => fixture(async root => {
  await writeFile(join(root, 'source.ts'), 'export const count = 1;\n', { mode: 0o600 });
  assert.equal((await readBoundFile(root, 'source.ts')).toString(), 'export const count = 1;\n');
  await symlink('source.ts', join(root, 'alias.ts'));
  await assert.rejects(readBoundFile(root, 'alias.ts'));
  await assert.rejects(readBoundFile(root, '../source.ts'));
  await assert.rejects(readBoundFile(root, '.ssh/id'));
  await link(join(root, 'source.ts'), join(root, 'hard.ts'));
  await assert.rejects(readBoundFile(root, 'source.ts'));
}));
test('source scan authenticates bytes and modes, skips only generated root git directory', async () => fixture(async root => {
  await mkdir(join(root, '.git')); await writeFile(join(root, '.git', 'ignored'), 'git metadata');
  await mkdir(join(root, 'src')); await mkdir(join(root, 'src', 'auth'));
  await writeFile(join(root, 'src', 'auth', 'login.ts'), 'known source\n', { mode: 0o600 });
  const entries = await scanSourceTree(root);
  assert.deepEqual(entries, [{ path: 'src/auth/login.ts', sha256: createHash('sha256').update('known source\n').digest('hex'), mode: 0o600 }]);
  await chmod(join(root, 'src', 'auth', 'login.ts'), 0o700);
  assert.equal((await scanSourceTree(root))[0].mode, 0o700);
  await writeFile(join(root, '.env'), 'not a real secret');
  await assert.rejects(scanSourceTree(root));
}));
test('omissions are rejected before reading their contents', async () => fixture(async root => {
  await writeFile(join(root, 'omitted.txt'), 'forbidden input');
  await assert.rejects(scanSourceTree(root, { omissions: ['omitted.txt'] }));
}));
test('root and nested directory symlinks fail closed', async () => fixture(async root => {
  await mkdir(join(root, 'real')); await writeFile(join(root, 'real', 'file.ts'), 'x');
  await symlink('real', join(root, 'alias'));
  await assert.rejects(readBoundFile(root, 'alias/file.ts'));
  await assert.rejects(scanSourceTree(join(root, 'alias')));
  await assert.rejects(scanSourceTree(root));
}));
test('bounded reads and scans reject oversized inputs without partial success', async () => fixture(async root => {
  await writeFile(join(root, 'a.ts'), '12345');
  await assert.rejects(readBoundFile(root, 'a.ts', { maxBytes: 4 }));
  await assert.rejects(scanSourceTree(root, { maxTotalBytes: 4 }));
  await writeFile(join(root, 'b.ts'), '1');
  await assert.rejects(scanSourceTree(root, { maxFiles: 1 }));
}));
test('source fingerprint checks refuse in-place mutation during related artifact reads', async () => fixture(async root => {
  await writeFile(join(root, 'a.ts'), 'before', { mode: 0o600 });
  await assert.rejects(scanSourceTree(root, { afterRead: async () => {
    await writeFile(join(root, 'a.ts'), 'after!');
  } }));
}));
test('final directory listing cannot hide an in-place leaf change after its hash', async () => fixture(async root => {
  const source = join(root, 'source'); await mkdir(source);
  await writeFile(join(source, 'main.ts'), 'before', { mode: 0o600 });
  const loader = join(root, 'race-loader.mjs');
  await writeFile(loader, `import {registerHooks} from 'node:module'; import * as fs from 'node:fs/promises';
    let listings=0;
    globalThis.__raceFs={...fs,readdir:async(...args)=>{const names=await fs.readdir(...args);
      if(names.includes('main.ts')&&++listings===4)await fs.writeFile(${JSON.stringify(join(source, 'main.ts'))},'after!');return names;}};
    registerHooks({resolve(s,c,next){if(s==='node:fs/promises')return {url:'race:fs',shortCircuit:true};return next(s,c);},
      load(u,c,next){if(u==='race:fs')return {format:'module',source:'export const {open,readdir,realpath}=globalThis.__raceFs;',shortCircuit:true};return next(u,c);}});`);
  const module = new URL('../dev-tools/continuation-provenance-fs.mjs', import.meta.url).href;
  await assert.rejects(promisify(execFile)(process.execPath, ['--import', loader, '--input-type=module', '-e',
    `const {scanSourceTree}=await import(${JSON.stringify(module)}); await scanSourceTree(${JSON.stringify(source)});`]),
  error => error.stderr.includes('continuation_workspace_unavailable'));
}));
