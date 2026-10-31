// Zaključavanje karte u Card editoru preko Syncthinga: data/locks/<kod>.json { who, since, heartbeat }.
// Tko uređuje kartu, osvježava heartbeat svakih 30 s; lock bez heartbeata 5 min je napušten.
// Nije sigurnosna zaštita, samo dogovor (kao "Ja sam"); ConflictError u store.js ostaje zadnja zaštita.

export const LOCK_DIR = 'data/locks';
export const HEARTBEAT_MS = 30_000;
export const STALE_MS = 5 * 60_000;
// Syncthing donese tuđi lock za nekoliko sekundi: nakon pisanja svog, provjeri još jednom.
export const SETTLE_MS = 4_000;

export const lockPath = id => `${LOCK_DIR}/${id}.json`;

// 'free' (nema locka ili je napušten), 'mine' ili 'other'.
export function lockState(lock, me, now = Date.now()) {
  if (!lock?.who) return 'free';
  const beat = Date.parse(lock.heartbeat ?? lock.since ?? '');
  if (!Number.isFinite(beat) || now - beat > STALE_MS) return 'free';
  return lock.who === me ? 'mine' : 'other';
}

export function newLock(me, now = new Date(), since = null) {
  return { who: me, since: since ?? now.toISOString(), heartbeat: now.toISOString() };
}
