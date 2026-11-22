// Art koji nijedna karta više ne koristi (Marko 2026-11-16). Zamijenjeni art (data/art/<kod>.<hash>.<ext>) ne briše
// se odmah: dok ga ništa ne koristi, karta ga nudi kao "Previous art" za vraćanje; Objava zapiše što je tada
// nekorišteno, a iduća Objava to obriše ako se u međuvremenu nije vratilo. Gumb Clean up (Tools) briše odmah.
// Bez I/O, isto za app i testove.

const IMG = /\.(?:png|jpe?g|webp)$/i;

// Putanje arta ("art/OP1-001.ab12cd34.png", "art/emblems/…") koje koriste karte, nacrti i zadnja Objava (njen Undo
// vraća stare karte i nacrte, pa i njihov art mora ostati).
export function artRefs(cards = [], drafts = {}, lastPublish = null) {
  const out = new Set();
  const add = c => { for (const k of ['art', 'emblem']) if (c?.[k]) out.add(String(c[k])); };
  for (const c of cards) add(c);
  for (const d of Object.values(drafts ?? {})) add(d);
  for (const c of lastPublish?.before?.cards ?? []) add(c);
  for (const d of Object.values(lastPublish?.drafts ?? {})) add(d);
  return out;
}

// Art iz popisa (putanje kao "art/…") koji ništa ne koristi.
export function unusedArt(paths, refs) {
  return paths.filter(p => IMG.test(p) && !refs.has(p)).sort();
}

// Kod pod kojim je art spremljen ("art/DQ1-012.ab12cd34.png" → "DQ1-012"), ili null (amblemi, drugo).
export function artCode(path) {
  const m = /^art\/([A-Za-z]{2,4}\d{1,2}-\d{3}(?:-\d+)?)\.[^/]+$/.exec(String(path ?? ''));
  return m ? m[1] : null;
}

// Prijašnji art jedne karte: nekorišteni art spremljen pod istim kodom kao njezin sadašnji art, inače pod njezinim
// kodom (bez amblema). Karta pomaknuta na drugi kod prije 22. 11. 2026. zadržala je art pod starim kodom, pa bi se
// po kodu karte nudio art karte koja je prije bila na tom kodu (2026-11-22).
export function previousArtOf(id, unused, art = null) {
  const code = artCode(art) ?? id;
  return unused.filter(p => p.startsWith(`art/${code}.`));
}

// Kad se kodovi pomiču: svaka datoteka arta spremljena pod kodom iz `codes` (Map stari kod → novi kod) dobiva novi
// kod u imenu. Vraća [[stara putanja, nova putanja]].
export function artMoves(files, codes) {
  const out = [];
  for (const p of files ?? []) {
    const c = artCode(p);
    if (c && codes.has(c)) out.push([p, p.replace(`art/${c}.`, `art/${codes.get(c)}.`)]);
  }
  return out;
}

// Što Objava briše: ono što je bilo nekorišteno već pri prošloj Objavi i još je nekorišteno.
export function artToDrop(lastUnused = [], unusedNow = []) {
  const now = new Set(unusedNow);
  return lastUnused.filter(p => now.has(p));
}
