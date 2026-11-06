import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { cleanPath, canWrite, canRemove, canList, atomicWrite } from '../server/fs-api.mjs';

test('paths that climb out, are absolute or odd are refused', () => {
  for (const p of ['', '/data/editor/drafts.json', '../data/editor/drafts.json', 'data/../server/config.local.json',
    'data//editor/drafts.json', 'data\\editor\\drafts.json', 'data/./editor/drafts.json', null, 5]) assert.equal(cleanPath(p), null, String(p));
  assert.equal(cleanPath('data/editor/drafts.json'), 'data/editor/drafts.json');
});

test('the phone may save drafts, locks, Claude requests, the wishlist, art and sets', () => {
  for (const p of ['data/editor/drafts.json', 'data/editor/notes.json', 'data/editor/history.json', 'data/editor/text-guide.json',
    'data/locks/OP1-014.json', 'data/fx-requests/OP1-014.json', 'data/text-requests/OP1-014.json', 'data/fx-wishlist.json',
    'data/art/OP1-014.1a2b3c4d.png', 'data/art/emblems/OP1-005.1a2b3c4d.webp', 'data/sets/sets.json', 'data/sets/OP1/icon.png', 'data/card-frames/hero/layout.json']) {
    assert.ok(canWrite(cleanPath(p)), p);
  }
});

test('Publish stays on the computer: the database, card images and the rest are refused', () => {
  for (const p of ['data/cards.json', 'data/changelog.json', 'data/images/OP1-014.1a2b3c4d.png', 'data/thumbs/OP1-014.1a2b3c4d.jpg',
    'data/editor/last-publish.json', 'data/traits.json', 'data/art/OP1-014.exe', 'data/fx-claude/OP1-014.json', 'data/text-claude/OP1-014.json',
    'decks/my-deck.json', 'server/config.local.json', 'data/locks/x.txt']) {
    assert.equal(canWrite(cleanPath(p)), false, p);
  }
  assert.ok(canRemove('data/locks/OP1-014.json'));
  assert.equal(canRemove('data/editor/drafts.json'), false);
  assert.ok(canList('data/locks'));
  assert.equal(canList('data'), false);
});

test('atomicWrite replaces the file whole and leaves no temp file', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'eb-fs-'));
  const file = path.join(dir, 'data', 'editor', 'drafts.json');
  await atomicWrite(file, '{"a":1}');
  await atomicWrite(file, Buffer.from('{"a":2}'));
  assert.equal(await fs.readFile(file, 'utf8'), '{"a":2}');
  assert.deepEqual(await fs.readdir(path.dirname(file)), ['drafts.json']);
  await fs.rm(dir, { recursive: true, force: true });
});
