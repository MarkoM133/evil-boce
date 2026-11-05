import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toTokens, toWords, head, withHead, headAt, withHeadAt, stripTerrain, withTerrain, coreBonus, coreEffect } from '../js/card-text.js';

test('card text: words in cards.json, tokens in the editor, and back', () => {
  const words = "[Range] Postroll Phase: Your Hero heals 3 HP and their Hero takes 3 DMG.";
  const tokens = '[RNG]Postroll Phase: Your Hero heals 3[HP] and their Hero takes 3[DMG].';
  assert.equal(toTokens(words), tokens);
  assert.equal(toWords(tokens), words);
  assert.equal(toTokens('the Hero with more HP gains +3000 Power.'), 'the Hero with more [HP] gains +3000[PWR].');
  assert.equal(toWords('the Hero with more [HP] gains +3000[PWR].'), 'the Hero with more HP gains +3000 Power.');
  assert.equal(toTokens("[Range] Postroll Phase: an Opponent's Hero in Range takes 3 DMG."), "[RNG]Postroll Phase: an Opponent's Hero in [RNG] takes 3[DMG].");
  assert.equal(toWords("[RNG]Postroll Phase: an Opponent's Hero in [RNG] takes 3[DMG]."), "[Range] Postroll Phase: an Opponent's Hero in Range takes 3 DMG.");
  const intercept = "[Range] Postroll Phase: Swap your Hero with another friendly Hero that is in an Opponent's Hero's Range.";
  assert.equal(toTokens(intercept), "[RNG]Postroll Phase: Swap your Hero with another friendly Hero that is in an Opponent's Hero's [RNG].");
  assert.equal(toWords(toTokens(intercept)), intercept);
  assert.equal(toTokens('in Combat range of an enemy'), 'in Combat range of an enemy');
  for (const [words, tokens] of [['You must discharge 1 Energy if', 'You must discharge 1[EN] if'],
    ['cost 2 more Energy this turn', 'cost 2 more [EN] this turn'], ['for every charged Energy their', 'for every charged [EN] their']]) {
    assert.equal(toTokens(words), tokens);
    assert.equal(toWords(tokens), words);
  }
  assert.equal(toTokens("Knockback an Opponent's Hero 3 spaces"), "Knockback an Opponent's Hero 3 spaces");
  assert.equal(toWords('**Battle Phase:** gain +1[KB]'), 'Battle Phase: gain +1 Knockback');
});

test('card text: phase, once per turn and range as toggles', () => {
  assert.deepEqual(head('[RNG]Postroll Phase Once Per Turn: Luffy may activate a Core.'), { range: true, phase: 'Postroll', once: true, rest: 'Luffy may activate a Core.' });
  assert.deepEqual(head('Each Hero gains +1[DMG].'), { range: false, phase: null, once: false, rest: 'Each Hero gains +1[DMG].' });
  assert.equal(withHead('Postroll Phase: Hit.', { range: true, phase: 'Battle', once: false }), '[RNG]Battle Phase: Hit.');
  assert.equal(withHead('[RNG]Battle Phase: Hit.', { range: false, phase: null, once: false }), 'Hit.');
});

test('card text: Stage terrain line and Core bonus', () => {
  assert.equal(stripTerrain('When this Stage is revealed, gain.\nTerrain: Ice'), 'When this Stage is revealed, gain.');
  assert.equal(withTerrain('When this Stage is revealed, gain.', 'Mud'), 'When this Stage is revealed, gain.\nTerrain: Mud');
  assert.deepEqual(coreBonus('+2000[PWR]'), { pwr: 2000 });
  assert.deepEqual(coreBonus('-1[KB]'), { kb: -1 });
  assert.equal(coreEffect({ pwr: -2000 }), '-2000[PWR]');
  assert.deepEqual(coreBonus('Lv2[DMG] x2000[PWR]'), {}, 'a number glued to a word is not a bonus');
});

test('card text: several effects, the toggles work on the effect under the caret', () => {
  const t = 'Roll Phase: Roll again.\n[RNG]Postroll Phase Once Per Turn: Heal 2[HP].\n- or this';
  assert.equal(headAt(t, 3).phase, 'Roll');
  const at = headAt(t, t.length);
  assert.deepEqual([at.phase, at.once, at.range], ['Postroll', true, true], 'a bullet belongs to the effect above it');
  assert.equal(withHeadAt(t, 3, { phase: 'Battle' }).text.split('\n')[0], 'Battle Phase: Roll again.');
  assert.equal(toWords('Roll Phase: x.\n[RNG]Battle Phase: y'), 'Roll Phase: x.\n[Range] Battle Phase: y');
  assert.equal(toTokens('Roll Phase: x.\n[Range] Battle Phase: y'), 'Roll Phase: x.\n[RNG]Battle Phase: y');
});
