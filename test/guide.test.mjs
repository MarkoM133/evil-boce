import { test } from 'node:test';
import assert from 'node:assert/strict';
import { avoidWarnings, suggest, guideMarkdown } from '../js/editor-guide.js';

const guide = {
  intro: 'Uniform phrases.',
  phrases: [{ label: 'Heal', text: 'heals 3 HP' }, { label: 'Knockback', text: "Knockback an Opponent's Hero 3 spaces" }, { label: 'Roll again', text: 'roll again' }],
  avoid: [{ find: '\\b(push|shove)\\b', say: 'Use Knockback.' }, { find: '([', say: 'broken pattern is skipped' }],
};

test('text guide: warnings from the avoid rules', () => {
  assert.deepEqual(avoidWarnings(guide, 'Push an Opponent\'s Hero 2 spaces.'), ['Use Knockback.']);
  assert.deepEqual(avoidWarnings(guide, 'Knockback an Opponent\'s Hero 2 spaces.'), []);
});

test('text guide: suggestions for the words before the caret and after [', () => {
  const t = 'Postroll Phase: Knockback an';
  const s = suggest(guide, t, t.length);
  assert.equal(s.from, t.indexOf('Knockback'));
  assert.deepEqual(s.items.map(i => i.insert), ["Knockback an Opponent's Hero 3 spaces"]);
  assert.equal(suggest(guide, 'Your Hero he', 12).items[0].insert, 'heals 3 HP');
  const b = suggest(guide, 'gains +2000 [', 13);
  assert.equal(b.from, 12);
  assert.ok(b.items.some(i => i.insert === ' Power'));
  assert.deepEqual(suggest(guide, 'x', 1).items, []);
});

test('text guide: markdown export lists phrases and rules', () => {
  const md = guideMarkdown(guide);
  assert.match(md, /\| Heal \| `heals 3 HP` \|/);
  assert.match(md, /- Use Knockback\./);
});

test('a rule with flags "" is case-sensitive', () => {
  const guide = { avoid: [{ find: '\\bOnce per turn\\b', flags: '', say: 'Write "Once Per Turn".' }] };
  assert.deepEqual(avoidWarnings(guide, 'Postroll Phase Once Per Turn: x'), []);
  assert.deepEqual(avoidWarnings(guide, 'Postroll Phase Once per turn: x'), ['Write "Once Per Turn".']);
});
