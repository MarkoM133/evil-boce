// Rastavljanje teksta efekta za renderer karata (oznake faze, RANGE, uvjet, natuknice).
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseEffect, richRuns } from '../js/render.js';

test('range, phase and the rest of the text', () => {
  const e = parseEffect('[Range] Postroll Phase: Knockback an Opponent\'s Hero 3 spaces.');
  assert.equal(e.range, true);
  assert.equal(e.phase, 'POSTROLL PHASE');
  assert.equal(e.once, false);
  assert.deepEqual(e.lines, [{ bullet: false, text: 'Knockback an Opponent\'s Hero 3 spaces.' }]);
});

test('once per turn, a condition and a short phase word', () => {
  const e = parseEffect('Battle Phase Once Per Turn: If you win this Battle, draw a card.');
  assert.equal(e.phase, 'BATTLE PHASE');
  assert.equal(e.once, true);
  assert.equal(e.cond, 'If you win this Battle,');
  assert.equal(e.lines[0].text, 'draw a card.');
  assert.equal(parseEffect('[Range] Postroll: All cards cost 2 more.').phase, 'POSTROLL PHASE');
});

test('a list becomes bullets; a phase alone has no lines', () => {
  const e = parseEffect('Postroll Phase: Your Opponent chooses:\n- You charge 2 Energy\n- Your Hero heals 3 HP');
  assert.deepEqual(e.lines.map(l => l.bullet), [false, true, true]);
  assert.equal(e.lines[2].text, 'Your Hero heals 3 HP');
  assert.deepEqual(parseEffect('Battle Phase:').lines, []);
  assert.equal(parseEffect('The equipped Hero takes +1 DMG.').phase, null);
});

test('stat words after a number or more/less are icons, the rest stays text', () => {
  assert.deepEqual(richRuns('heals 3 HP and takes 3 DMG'), [{ text: 'heals 3' }, { icon: 'hp' }, { text: ' and takes 3' }, { icon: 'dmg' }]);
  assert.deepEqual(richRuns('the Hero with more HP gains +3000 Power.'), [{ text: 'the Hero with more' }, { icon: 'hp' }, { text: ' gains +3000' }, { icon: 'pwr' }, { text: '.' }]);
  assert.deepEqual(richRuns("Knockback an Opponent's Hero 3 spaces"), [{ text: "Knockback an Opponent's Hero 3 spaces" }]);
  assert.deepEqual(richRuns('for every {Sword}'), [{ text: 'for every ' }, { text: 'Sword', bold: true }]);
  assert.deepEqual(richRuns('hits for DMG 5'), [{ text: 'hits for ' }, { icon: 'dmg' }, { text: ' 5' }], 'HP and DMG are icons without a number too');
});
