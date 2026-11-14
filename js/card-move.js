// Moving an unpublished card to another code in its set (Marko 2026-11-14): heroes first in a set
// whose cards are made in any order. A code is free until Publish fixes it: published cards never move, and the
// unpublished cards between the old and the new place shift one place along (an empty code stops the shift).
// Pure: the Card editor applies the plan to drafts, notes, history and Claude's answers.

const setOf = id => id.split('-')[0];
const numOf = id => Number(id.slice(setOf(id).length + 1));
const codeOf = (set, n) => `${set}-${String(n).padStart(3, '0')}`;

// "5", "005" or "DQ1-005" → "DQ1-005"; null when it is none of them or names another set.
export function targetCode(set, answer) {
  const s = String(answer ?? '').trim().toUpperCase();
  const m = /^(?:([A-Z]{2,4}\d{1,2})-)?0*(\d{1,4})$/.exec(s);
  if (!m || (m[1] && m[1] !== set) || Number(m[2]) < 1) return null;
  return codeOf(set, Number(m[2]));
}

// from: the card to move; to: its new code; published: every code a published card holds (deleted ones too);
// unpublished: the codes of new cards that are only drafts. Returns Map(old code → new code) of every card whose
// code changes (empty when nothing moves); throws an Error a person can read when the move is not allowed.
export function planMove({ from, to, published, unpublished }) {
  const set = setOf(from);
  if (published.has(from)) throw new Error(`${from} is published: its code is fixed.`);
  if (!unpublished.has(from)) throw new Error(`${from} is not saved yet: save it first.`);
  if (!to || setOf(to) !== set || !Number.isFinite(numOf(to)) || numOf(to) < 1) throw new Error(`Pick a code in set ${set}, e.g. ${codeOf(set, 1)}.`);
  if (published.has(to)) throw new Error(`${to} is published: its code is fixed. Pick a code that is free or not published.`);
  const a = numOf(from);
  const b = numOf(to);
  if (a === b) return new Map();
  const at = new Map();
  for (const id of unpublished) if (setOf(id) === set) at.set(numOf(id), id);
  const lo = Math.min(a, b);
  const hi = Math.max(a, b);
  const places = [];
  for (let n = lo; n <= hi; n++) if (!published.has(codeOf(set, n))) places.push(n);
  if (b > a) places.reverse();
  // Walk from the new place towards the old one, each card taking the place of the next; the old place is empty
  // by then, so the walk always ends.
  let carry = from;
  at.delete(a);
  for (const n of places) {
    const was = at.get(n) ?? null;
    at.set(n, carry);
    carry = was;
    if (!carry) break;
  }
  const out = new Map();
  for (const [n, id] of at) if (id !== codeOf(set, n)) out.set(id, codeOf(set, n));
  return out;
}

// { id: value } with the keys renamed by the plan (a moved key never overwrites one that stays).
export function renameKeys(obj, plan) {
  const out = {};
  for (const [id, v] of Object.entries(obj ?? {})) if (!plan.has(id)) out[id] = v;
  for (const [id, v] of Object.entries(obj ?? {})) if (plan.has(id)) out[plan.get(id)] = v;
  return out;
}

// Drafts after the move: keys renamed, and Combo ingredients that name a moved card follow it.
export function moveDrafts(cards, plan) {
  const out = renameKeys(cards, plan);
  for (const d of Object.values(out)) {
    if (Array.isArray(d?.ingredients)) d.ingredients = d.ingredients.map(id => plan.get(id) ?? id);
  }
  return out;
}
