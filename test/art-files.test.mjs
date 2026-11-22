// Art koji nijedna karta ne koristi: vraćanje, brisanje pri drugoj Objavi, Clean up (Marko 2026-11-16).
import test from 'node:test';
import assert from 'node:assert/strict';
import { artRefs, unusedArt, previousArtOf, artToDrop, artCode, artMoves } from '../js/art-files.js';

const cards = [
  { id: 'DQ1-005', art: 'art/DQ1-005.new.png' },
  { id: 'DQ1-001', art: 'art/DQ1-001.a.png', emblem: 'art/emblems/DQ1-001.e.png' },
];
const files = ['art/DQ1-005.new.png', 'art/DQ1-005.old.jpg', 'art/DQ1-005.older.png', 'art/DQ1-001.a.png', 'art/emblems/DQ1-001.e.png',
  'art/emblems/DQ1-001.olde.png', 'art/readme.txt', 'art/DQ1-008.x.png'];

test('art nobody uses: cards, drafts and the last Publish (its Undo) keep theirs', () => {
  const refs = artRefs(cards, { 'DQ1-008': { art: 'art/DQ1-008.x.png' } }, { before: { cards: [{ id: 'DQ1-005', art: 'art/DQ1-005.older.png' }] }, drafts: {} });
  assert.deepEqual(unusedArt(files, refs), ['art/DQ1-005.old.jpg', 'art/emblems/DQ1-001.olde.png']);
});

test('a card offers its own old art back, never an emblem or another card', () => {
  const unused = unusedArt(files, artRefs(cards));
  assert.deepEqual(previousArtOf('DQ1-005', unused), ['art/DQ1-005.old.jpg', 'art/DQ1-005.older.png']);
  assert.deepEqual(previousArtOf('DQ1-001', unused), []);
});

test('a Publish drops only what was unused at the Publish before and still is', () => {
  assert.deepEqual(artToDrop(['art/A.1.png', 'art/B.1.png'], ['art/B.1.png', 'art/C.1.png']), ['art/B.1.png']);
  assert.deepEqual(artToDrop(undefined, ['art/C.1.png']), []);
});

test('a card moved to another code finds its own previous art, not the art of the card that held the code (2026-11-22)', () => {
  const unused = ['art/DQ1-012.aaaa1111.png', 'art/DQ1-012.bbbb2222.png', 'art/DQ1-005.cccc3333.png'];
  assert.equal(artCode('art/DQ1-012.aaaa1111.png'), 'DQ1-012');
  assert.equal(artCode('art/emblems/OP1.png'), null);
  assert.equal(artCode('art/DQ1-010-1.dddd4444.webp'), 'DQ1-010-1');
  // Moved from 012 to 005: its art is still saved under 012.
  assert.deepEqual(previousArtOf('DQ1-005', unused, 'art/DQ1-012.eeee5555.png'), ['art/DQ1-012.aaaa1111.png', 'art/DQ1-012.bbbb2222.png']);
  // A card with no art, or art under its own code, as before.
  assert.deepEqual(previousArtOf('DQ1-005', unused), ['art/DQ1-005.cccc3333.png']);
  assert.deepEqual(previousArtOf('DQ1-005', unused, 'art/DQ1-005.ffff6666.png'), ['art/DQ1-005.cccc3333.png']);
});

test('moving codes renames the art saved under the moved codes (2026-11-22)', () => {
  const files = ['art/DQ1-005.a.png', 'art/DQ1-006.b.png', 'art/DQ1-006.c.jpg', 'art/DQ1-007.d.png', 'art/emblems/DQ1.png'];
  const moves = artMoves(files, new Map([['DQ1-005', 'DQ1-006'], ['DQ1-006', 'DQ1-007']]));
  assert.deepEqual(moves, [['art/DQ1-005.a.png', 'art/DQ1-006.a.png'], ['art/DQ1-006.b.png', 'art/DQ1-007.b.png'], ['art/DQ1-006.c.jpg', 'art/DQ1-007.c.jpg']]);
  assert.deepEqual(artMoves(files, new Map()), []);
});
