import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { sha256Js, sha256Hex } from '../js/importer.js';

test('the JS SHA-256 (pages without crypto.subtle) matches the real one', () => {
  for (const bytes of [new Uint8Array(0), new TextEncoder().encode('abc'), new Uint8Array(55).fill(7), new Uint8Array(64).fill(1),
    new Uint8Array(1000).map((_, i) => (i * 31) & 255)]) {
    assert.equal(sha256Js(bytes), createHash('sha256').update(bytes).digest('hex'));
  }
});

test('sha256Hex gives the same hash with and without crypto.subtle', async () => {
  const bytes = new TextEncoder().encode('Evil Boće');
  const withSubtle = await sha256Hex(bytes);
  const subtle = globalThis.crypto;
  Object.defineProperty(globalThis, 'crypto', { value: undefined, configurable: true });
  try {
    assert.equal(await sha256Hex(bytes), withSubtle);
  } finally {
    Object.defineProperty(globalThis, 'crypto', { value: subtle, configurable: true });
  }
});
