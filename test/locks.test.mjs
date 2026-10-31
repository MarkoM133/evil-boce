import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lockState, newLock, lockPath, STALE_MS } from '../js/locks.js';

test('card locks: free, mine, other, stale after five minutes', () => {
  const now = Date.parse('2026-10-31T10:00:00Z');
  const lock = newLock('Tarik', new Date(now - 60_000));
  assert.equal(lockState(null, 'Marko', now), 'free');
  assert.equal(lockState(lock, 'Marko', now), 'other');
  assert.equal(lockState(lock, 'Tarik', now), 'mine');
  assert.equal(lockState(lock, 'Marko', now + STALE_MS), 'free');
  assert.equal(lockState({ who: 'Tarik', heartbeat: 'nonsense' }, 'Marko', now), 'free');
  assert.equal(lockPath('OP1-001'), 'data/locks/OP1-001.json');
  const kept = newLock('Tarik', new Date(now), lock.since);
  assert.equal(kept.since, lock.since);
});
