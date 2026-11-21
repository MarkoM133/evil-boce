// Pojmovi pravila: prepoznavanje u tekstu karte (Marko 2026-11-21, Coco Jumbo).
import test from 'node:test';
import assert from 'node:assert/strict';
import { termNames, splitTerms, termsOfCard, subtypes } from '../js/terms.js';
import { richRuns, setRuleTerms } from '../js/render.js';

const TERMS = [
  { name: 'Companion', text: 'A token on the map.', subtype: true },
  { name: 'hide inside', text: 'The Hero leaves the table.' },
  { name: 'hide', text: 'A shorter term.' },
];

test('terms in the text, longest first, whole words only, case kept', () => {
  const names = termNames(TERMS);
  assert.deepEqual(names, ['hide inside', 'hide'], 'a subtype is not a word in the text');
  const parts = splitTerms('A friendly Hero may pay 1 Energy to Hide Inside.', names);
  assert.deepEqual(parts, [{ text: 'A friendly Hero may pay 1 Energy to ' }, { text: 'Hide Inside', term: 'hide inside' }, { text: '.' }]);
  assert.deepEqual(splitTerms('Hideout and hides stay plain.', names), [{ text: 'Hideout and hides stay plain.' }]);
  assert.deepEqual(splitTerms('No terms here.', []), [{ text: 'No terms here.' }]);
});

test('what a card uses: terms in the text and its subtype', () => {
  const card = { text: 'Postroll Phase: A friendly Hero may hide inside.', subtype: 'companion' };
  assert.deepEqual(termsOfCard(card, TERMS).sort(), ['Companion', 'hide inside']);
  assert.deepEqual(subtypes(TERMS), ['Companion']);
});

test('the renderer draws a term bold and marked, icons still work around it', () => {
  setRuleTerms(TERMS);
  const runs = richRuns('Pay 1 Energy to hide inside.');
  assert.ok(runs.some(r => r.term && r.bold && r.text === 'hide inside'), JSON.stringify(runs));
  assert.ok(runs.some(r => r.icon === 'energy'), 'the Energy icon is still there');
  setRuleTerms([]);
  assert.ok(!richRuns('Pay 1 Energy to hide inside.').some(r => r.term), 'no terms, plain text');
});
