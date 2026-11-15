import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lockState, newLock, lockPath, pickLock, lockIdOf, isConflictCopy, isLive, STALE_MS, SETTLE_MS, HEARTBEAT_MS } from '../js/locks.js';
import { canRemove, canWrite, canList } from '../server/fs-api.mjs';

test('card locks: free, mine, other, stale after two minutes', () => {
  const now = Date.parse('2026-10-31T10:00:00Z');
  const lock = newLock('Tarik', new Date(now - 60_000));
  assert.equal(lockState(null, 'Marko', now), 'free');
  assert.equal(lockState(lock, 'Marko', now), 'other');
  assert.equal(lockState(lock, 'Tarik', now), 'mine');
  assert.equal(lockState(lock, 'Marko', now + STALE_MS), 'free');
  assert.equal(STALE_MS, 2 * 60_000);
  assert.equal(lockState({ who: 'Tarik', heartbeat: 'nonsense' }, 'Marko', now), 'free');
  assert.equal(lockPath('OP1-001'), 'data/locks/OP1-001.json');
  const kept = newLock('Tarik', new Date(now), lock.since);
  assert.equal(kept.since, lock.since);
});

test('the second look waits for Syncthing (it holds a change 10 s before sending)', () => {
  assert.ok(SETTLE_MS >= 15_000 && SETTLE_MS < HEARTBEAT_MS);
});

test('the same name in another window is a twin, not mine', () => {
  const now = Date.parse('2026-11-15T01:00:00Z');
  const pc = newLock('Marko', new Date(now), null, 'tabA');
  assert.equal(lockState(pc, 'Marko', now, 'tabA'), 'mine');
  assert.equal(lockState(pc, 'Marko', now, 'tabB'), 'twin');
  assert.equal(lockState(pc, 'Tarik', now, 'tabB'), 'other');
  // A lock from an older Card Studio has no tab: it is mine.
  assert.equal(lockState(newLock('Marko', new Date(now)), 'Marko', now, 'tabB'), 'mine');
  // Without a tab of my own (Sets page) my name is mine.
  assert.equal(lockState(pc, 'Marko', now), 'mine');
});

test('two copies of one lock (Syncthing conflict): who opened it first keeps the card, unless someone took it over', () => {
  const t = Date.parse('2026-11-15T00:47:00Z');
  const marko = newLock('Marko', new Date(t + 10_000), new Date(t).toISOString(), 'a');
  const tarik = newLock('Tarik', new Date(t + 16_000), null, 'b');
  assert.equal(pickLock([tarik, marko], t + 20_000).who, 'Marko');
  assert.equal(pickLock([marko, tarik], t + 20_000).who, 'Marko');
  const over = newLock('Tarik', new Date(t + 30_000), null, 'b', true);
  assert.equal(pickLock([marko, over], t + 31_000).who, 'Tarik');
  const back = newLock('Marko', new Date(t + 40_000), null, 'a', true);
  assert.equal(pickLock([over, back], t + 41_000).who, 'Marko');
  // A stale copy does not count; none live is no lock.
  assert.equal(pickLock([marko, tarik], t + 16_000 + STALE_MS + 1), null);
  assert.equal(pickLock([{ ...marko, heartbeat: new Date(t - STALE_MS).toISOString() }, tarik], t + 20_000).who, 'Tarik');
  assert.equal(pickLock([], t), null);
  assert.ok(isLive(tarik, t + 20_000));
});

test('lock file names, Syncthing conflict copies included', () => {
  assert.equal(lockIdOf('DQ1-017.json'), 'DQ1-017');
  assert.equal(lockIdOf('DQ1-017.sync-conflict-20261115-014736-J4CP4FM.json'), 'DQ1-017');
  assert.equal(lockIdOf('notes.txt'), null);
  assert.ok(isConflictCopy('DQ1-017.sync-conflict-20261115-014736-J4CP4FM.json'));
  assert.ok(!isConflictCopy('DQ1-017.json'));
  // The phone (through the server) may list, write and clear them too.
  assert.ok(canList('data/locks'));
  assert.ok(canWrite('data/locks/DQ1-017.json'));
  assert.ok(canRemove('data/locks/DQ1-017.sync-conflict-20261115-014736-J4CP4FM.json'));
  assert.ok(!canRemove('data/locks/../cards.json'));
});
