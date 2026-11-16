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

// Prijašnji art jedne karte: nekorišteni art s njezinim kodom (bez amblema).
export function previousArtOf(id, unused) {
  return unused.filter(p => p.startsWith(`art/${id}.`));
}

// Što Objava briše: ono što je bilo nekorišteno već pri prošloj Objavi i još je nekorišteno.
export function artToDrop(lastUnused = [], unusedNow = []) {
  const now = new Set(unusedNow);
  return lastUnused.filter(p => now.has(p));
}
