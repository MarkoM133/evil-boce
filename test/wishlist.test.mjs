import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { addWishes, WISHLIST } from '../server/fx-claude.mjs';

test('two conditions that both start with IF are two wishlist items', async () => {
  const drive = await fs.mkdtemp(path.join(os.tmpdir(), 'eb-wish-'));
  const card = { id: 'X-001', name: 'X', who: 'Marko' };
  await addWishes(drive, card, [{ kind: 'condition', word: 'IF HERO {Name}', meaning: 'a', why: 'b', fx: 'ROLL IF HERO {Luffy}: ROLL_AGAIN' }]);
  await addWishes(drive, { ...card, id: 'X-002' }, [{ kind: 'condition', word: 'IF MORE_ENERGY', meaning: 'c', why: 'd', fx: 'BATTLE IF MORE_ENERGY: BUFF SELF PWR 3000' }]);
  const list = JSON.parse(await fs.readFile(path.join(drive, WISHLIST), 'utf8'));
  assert.deepEqual(list.items.map(i => i.key).sort(), ['condition:HERO', 'condition:MORE_ENERGY']);
  await fs.rm(drive, { recursive: true, force: true });
});
