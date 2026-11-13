import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { inside, repoFile } from '../server/static-path.mjs';

// A small repo: the web app, the server's folder with its secret, private docs, git.
async function repo() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'eb-static-'));
  for (const [file, text] of [['index.html', 'app'], ['js/app.js', 'js'], ['css/style.css', 'css'],
    ['server/config.local.json', 'SECRET'], ['.git/config', 'git'], ['docs/private/plan.md', 'plan'],
    ['node_modules/x/index.js', 'x'], ['game/project.godot', 'game'], ['.gitignore', 'ignore']]) {
    await fs.mkdir(path.join(root, path.dirname(file)), { recursive: true });
    await fs.writeFile(path.join(root, file), text);
  }
  return root;
}

// The path as the server gets it: the URL's path, decoded once.
const url = u => decodeURIComponent(new URL(u, 'http://x').pathname);

test('the web app goes to everyone', async () => {
  const root = await repo();
  for (const u of ['/', '/index.html', '/js/app.js', '/css/style.css']) {
    const got = await repoFile(root, url(u), false);
    assert.ok(got.file, u);
  }
  assert.equal(await fs.readFile((await repoFile(root, url('/'), false)).file, 'utf8'), 'app');
});

test('the server folder, git and packages go to nobody, however the path is written', async () => {
  const root = await repo();
  const tries = ['/server/config.local.json', '/js/..%2Fserver/config.local.json', '/server%5Cconfig.local.json',
    '/js/..%5Cserver%5Cconfig.local.json', '/SERVER/config.local.json', '/js/%2E%2E/server/config.local.json',
    '/js/..%2F.git/config', '/.git/config', '/js/..%2Fnode_modules/x/index.js', '/.gitignore', '/css/..%2F.gitignore'];
  for (const local of [false, true])
    for (const u of tries) {
      const got = await repoFile(root, url(u), local);
      assert.equal(got.file, undefined, `${u} (local ${local})`);
      assert.ok(got.status === 404 || got.status === 403, u);
    }
});

test('the rest of the repo is for this computer only', async () => {
  const root = await repo();
  for (const u of ['/docs/private/plan.md', '/js/..%2Fdocs/private/plan.md', '/game/project.godot']) {
    assert.equal((await repoFile(root, url(u), false)).status, 404, u);
    assert.ok((await repoFile(root, url(u), true)).file, u);
  }
});

test('nothing outside the repo, and a missing file is not found', async () => {
  const root = await repo();
  assert.equal((await repoFile(root, url('/js/..%2F..%2F..%2Fwindows/win.ini'), true)).file, undefined);
  assert.equal((await repoFile(root, '/js/nothing.js', false)).status, 404);
  assert.equal(inside(root, '/../x'), null);
  assert.ok(inside(root, '/js/app.js'));
});
