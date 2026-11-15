// Zaključavanje karte u Card editoru preko Syncthinga: data/locks/<kod>.json { who, since, heartbeat, tab, over }.
// Tko uređuje kartu, osvježava heartbeat svakih 30 s; lock bez heartbeata 2 min je napušten.
// Nije sigurnosna zaštita, samo dogovor (kao "Ja sam"); ConflictError u store.js ostaje zadnja zaštita.
//
// Popravci (Marko 2026-11-15, DQ1-017 su on i Tarik zaključali u istoj sekundi):
// - Syncthing čeka 10 s prije slanja: druga provjera je nakon 20 s, ne 4.
// - Kad oba stroja pišu istovremeno, Syncthing jednu verziju spremi kao <kod>.sync-conflict-….json. Sve žive
//   verzije se čitaju zajedno: kartu zadrži onaj tko ju je ranije otvorio, osim kad je netko kliknuo Take over
//   (over: true), onda najnoviji Take over. Pobjednik prepiše glavni lock i obriše konfliktne kopije.
// - tab: isto ime u drugom prozoru ili na mobitelu je 'twin', ne 'mine'.

export const LOCK_DIR = 'data/locks';
export const HEARTBEAT_MS = 30_000;
// Skriveni tab osvježava barem jednom u minuti, pa 2 min ne oslobodi kartu koja je stvarno otvorena.
export const STALE_MS = 2 * 60_000;
// Syncthing donese tuđi lock za 10 do 15 s: nakon pisanja svog, provjeri još jednom.
export const SETTLE_MS = 20_000;
// Bez ijednog unosa toliko dugo (i bez nespremljenog) lock se pusti sam.
export const IDLE_MS = 15 * 60_000;

export const lockPath = id => `${LOCK_DIR}/${id}.json`;

const CONFLICT = '.sync-conflict-';
// Kod karte iz imena datoteke u data/locks (i za konfliktne kopije Syncthinga); null ako nije lock.
export function lockIdOf(file) {
  if (!file.endsWith('.json')) return null;
  const base = file.slice(0, -5);
  const i = base.indexOf(CONFLICT);
  return i >= 0 ? base.slice(0, i) : base;
}
export const isConflictCopy = file => file.includes(CONFLICT);

const beatOf = lock => Date.parse(lock?.heartbeat ?? lock?.since ?? '');
export const isLive = (lock, now = Date.now()) => !!lock?.who && Number.isFinite(beatOf(lock)) && now - beatOf(lock) <= STALE_MS;

// 'free' (nema locka ili je napušten), 'mine', 'twin' (moje ime, drugi prozor) ili 'other'.
export function lockState(lock, me, now = Date.now(), tab = null) {
  if (!isLive(lock, now)) return 'free';
  if (lock.who !== me) return 'other';
  return tab && lock.tab && lock.tab !== tab ? 'twin' : 'mine';
}

// Od svih verzija locka jedne karte (glavni + konfliktne kopije) ona koja vrijedi; null ako nijedna nije živa.
export function pickLock(copies, now = Date.now()) {
  const live = copies.filter(l => isLive(l, now));
  if (!live.length) return null;
  const t = l => Date.parse(l.since ?? l.heartbeat);
  const over = live.filter(l => l.over);
  if (over.length) return over.sort((a, b) => t(b) - t(a))[0];
  return live.sort((a, b) => t(a) - t(b) || String(a.who).localeCompare(String(b.who)) || String(a.tab ?? '').localeCompare(String(b.tab ?? '')))[0];
}

export function newLock(me, now = new Date(), since = null, tab = null, over = false) {
  return { who: me, since: since ?? now.toISOString(), heartbeat: now.toISOString(), ...(tab ? { tab } : {}), ...(over ? { over: true } : {}) };
}
