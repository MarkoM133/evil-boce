// Rastavljanje teksta efekta za renderer karata (oznake faze, RANGE, uvjet, natuknice).
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseEffect, parseEffects, richRuns, statBonusLines } from '../js/render.js';

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

test('"Range" with a capital is the range icon with a space; "range" stays text', () => {
  assert.deepEqual(richRuns('all other Heroes in Range take 2 DMG'), [{ text: 'all other Heroes in ' }, { icon: 'rng' }, { text: ' take 2' }, { icon: 'dmg' }]);
  assert.deepEqual(richRuns("that is in an Opponent's Hero's Range."), [{ text: "that is in an Opponent's Hero's " }, { icon: 'rng' }, { text: '.' }]);
  assert.deepEqual(richRuns('in Combat range of an enemy'), [{ text: 'in Combat range of an enemy' }]);
});

test('Energy is a diamond icon: glued to its number, a space after a word', () => {
  assert.deepEqual(richRuns('You must discharge 1 Energy if'), [{ text: 'You must discharge 1' }, { icon: 'energy' }, { text: ' if' }]);
  assert.deepEqual(richRuns('cost 2 more Energy this turn'), [{ text: 'cost 2 more ' }, { icon: 'energy' }, { text: ' this turn' }]);
  assert.deepEqual(richRuns('for every charged Energy their'), [{ text: 'for every charged ' }, { icon: 'energy' }, { text: ' their' }]);
});

test('stat words after a number or more/less are icons, the rest stays text', () => {
  assert.deepEqual(richRuns('heals 3 HP and takes 3 DMG'), [{ text: 'heals 3' }, { icon: 'hp' }, { text: ' and takes 3' }, { icon: 'dmg' }]);
  assert.deepEqual(richRuns('the Hero with more HP gains +3000 Power.'), [{ text: 'the Hero with more ' }, { icon: 'hp' }, { text: ' gains +3000' }, { icon: 'pwr' }, { text: '.' }]);
  // "the most Power" (Onigashima, Marko 2026-11-07) is an icon too.
  assert.deepEqual(richRuns('with the most Power gets'), [{ text: 'with the most ' }, { icon: 'pwr' }, { text: ' gets' }]);
  assert.deepEqual(richRuns("Knockback an Opponent's Hero 3 spaces"), [{ text: "Knockback an Opponent's Hero 3 spaces" }]);
  assert.deepEqual(richRuns('for every {Sword}'), [{ text: 'for every ' }, { text: 'Sword', bold: true, tag: true }]);
  assert.deepEqual(richRuns('hits for DMG 5'), [{ text: 'hits for ' }, { icon: 'dmg' }, { text: ' 5' }], 'HP and DMG are icons without a number too');
});

test('several effects: each line with a phase or [Range] starts its own effect', () => {
  const blocks = parseEffects('Roll Phase: You may roll again.\nPostroll Phase Once Per Turn: Heal 2 HP.\n- or this');
  assert.deepEqual(blocks.map(b => [b.phase, b.once, b.lines.length]), [['ROLL PHASE', false, 1], ['POSTROLL PHASE', true, 2]]);
  assert.equal(parseEffects('The equipped Hero takes +1 DMG.').length, 1);
});

test('colour bonuses that are only +N stat leave the text for the bonus boxes; sentences and minus stay right', () => {
  const { rest, chips } = statBonusLines('Battle Phase:\nYellow Bonus: +1 DMG.\nCyan / Purple Bonus: +1000 Power.\nRed Bonus: -1 KB.\nGreen Bonus: It also heals 2 HP.');
  assert.equal(rest, 'Battle Phase:\nGreen Bonus: It also heals 2 HP.');
  assert.deepEqual(chips, [
    { stat: 'dmg', value: 1, colors: ['Yellow'] },
    { stat: 'pwr', value: 1000, colors: ['Cyan', 'Purple'] },
    { stat: 'kb', value: -1, colors: ['Red'] },
  ]);
  assert.deepEqual(parseEffect('Purple Bonus: -1 KB.').lines, [{ bullet: false, text: '-1 KB.' }]);
});
