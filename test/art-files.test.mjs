// Art koji nijedna karta ne koristi: vraćanje, brisanje pri drugoj Objavi, Clean up (Marko 2026-11-16).
import test from 'node:test';
import assert from 'node:assert/strict';
import { artRefs, unusedArt, previousArtOf, artToDrop } from '../js/art-files.js';

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
