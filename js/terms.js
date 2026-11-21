// Pojmovi pravila (Marko 2026-11-21): karte se pišu rečenicama, a pojam koji treba objašnjenje ("hide inside") je na
// karti zlatan i podebljan, s okvirom na hover u igri. Tekst okvira piše se jednom (Card editor › Words › Terms) i isti
// je na svakoj karti. Pojam s oznakom "subtype" (Companion) je mala zlatna oznaka uz vrstu karte, ne riječ u tekstu.
// data/terms.json u zajedničkom folderu: { version, terms: [{ name, text, subtype? }] }. Bez I/O, isto za app i testove.

export const TERMS_PATH = 'data/terms.json';

export const emptyTerms = () => ({ version: 1, terms: [] });

const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Words of the text that are terms (not subtypes), longest first, so "hide inside" wins over "hide".
export function termNames(terms) {
  return [...new Set((terms ?? []).filter(t => t?.name && !t.subtype).map(t => String(t.name).trim()).filter(Boolean))]
    .sort((a, b) => b.length - a.length);
}

export function termRegex(names) {
  if (!names?.length) return null;
  return new RegExp(`(?<![\\p{L}\\p{N}])(${names.map(esc).join('|')})(?![\\p{L}\\p{N}])`, 'giu');
}

// The text in pieces: [{ text }, { text, term: 'hide inside' }, …]. Case does not matter; the card's own spelling stays.
export function splitTerms(s, names) {
  const re = termRegex(names);
  const text = String(s ?? '');
  if (!re) return [{ text }];
  const out = [];
  let last = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > last) out.push({ text: text.slice(last, m.index) });
    out.push({ text: m[0], term: names.find(n => n.toLowerCase() === m[0].toLowerCase()) ?? m[0] });
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push({ text: text.slice(last) });
  return out.length ? out : [{ text }];
}

// Which terms a card uses: in its text, and its subtype.
export function termsOfCard(card, terms) {
  const names = termNames(terms);
  const found = new Set(splitTerms(card?.text ?? '', names).filter(p => p.term).map(p => p.term));
  const sub = (terms ?? []).find(t => t.subtype && card?.subtype && t.name.toLowerCase() === String(card.subtype).toLowerCase());
  if (sub) found.add(sub.name);
  return [...found];
}

export const subtypes = terms => (terms ?? []).filter(t => t?.subtype && t.name).map(t => t.name);
