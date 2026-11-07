import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decorate, comboColors, combosOf, isIngredient, comboProblems, touchedIngredients, nextComboId } from '../js/combo.js';
import { applyDrafts } from '../js/importer.js';
import { DECK_TYPES } from '../js/parse.js';

const cards = [
  { id: 'OP1-024', name: 'Thunder Bagua', type: 'Action', color: 'Blue' },
  { id: 'OP1-031', name: 'Ikoku', type: 'Action', color: 'Green' },
  { id: 'OP1-012', name: 'Wado Ichimonji', type: 'Equipment', color: 'Yellow' },
  { id: 'OP1-009', name: 'Observation Haki', type: 'Action', color: 'None' },
  { id: 'CB-001', name: 'Conquest of the Sea', type: 'Combo', ingredients: ['OP1-024', 'OP1-031'], extraCost: 2, introducedIn: 'OP1' },
];

test('a combo takes the colours and names of its two cards; its cards get the spark', () => {
  const c = decorate(cards[4], cards);
  assert.deepEqual(c.comboColors, ['Blue', 'Green']);
  assert.deepEqual(c.ingredientNames, ['Thunder Bagua', 'Ikoku']);
  assert.equal(decorate(cards[0], cards).comboMark, true);
  assert.equal(decorate(cards[2], cards).comboMark, undefined, 'not an ingredient: no spark');
  assert.ok(isIngredient(cards, 'OP1-031'));
  assert.deepEqual(combosOf(cards, 'OP1-024').map(c => c.id), ['CB-001']);
});

test('colourless cards add no colour; two of the same colour are one', () => {
  assert.deepEqual(comboColors(cards, { ingredients: ['OP1-009', 'OP1-024'] }), ['Blue']);
  assert.deepEqual(comboColors(cards, { ingredients: ['OP1-024', 'OP1-024'] }), ['Blue']);
  assert.deepEqual(comboColors(cards, { ingredients: ['OP1-009'] }), ['None']);
});

test('a combo needs two different Action or Assist cards and an X', () => {
  assert.deepEqual(comboProblems(cards, cards[4]), []);
  assert.match(comboProblems(cards, { ingredients: ['OP1-024', ''], extraCost: 1 })[0], /exactly two/);
  assert.match(comboProblems(cards, { ingredients: ['OP1-024', 'OP1-024'], extraCost: 1 })[0], /different/);
  assert.match(comboProblems(cards, { ingredients: ['OP1-024', 'OP1-012'], extraCost: 1 })[0], /only Action and Assist/);
  assert.match(comboProblems(cards, { ingredients: ['OP1-024', 'OP1-031'] })[0], /extra cost/);
});

test('changing a combo touches its old and new cards; codes count up', () => {
  assert.deepEqual(touchedIngredients({ ingredients: ['A', 'B'] }, { ingredients: ['B', 'C'] }), ['A', 'B', 'C']);
  assert.equal(nextComboId(cards), 'CB-002');
  assert.equal(nextComboId([]), 'CB-001');
});

test('Publish keeps the combo fields, makes the combo landscape, and a combo never counts as a deck card', () => {
  const db = { version: 3, cards: cards.slice(0, 4) };
  const { db: next } = applyDrafts(db, { 'CB-001': { new: true, ...cards[4], text: 'Battle Phase: x' } });
  const cb = next.cards.find(c => c.id === 'CB-001');
  assert.deepEqual(cb.ingredients, ['OP1-024', 'OP1-031']);
  assert.equal(cb.extraCost, 2);
  assert.equal(cb.introducedIn, 'OP1');
  assert.equal(cb.landscape, true);
  assert.equal(DECK_TYPES.includes('Combo'), false);
});
