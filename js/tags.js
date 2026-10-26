// Pravilo prvog taga (odluka 2026-10-26): prvi tag karte kaže tko je smije u deck
// (i u igri): General = svaki heroj boje karte; alias heroja ("Giorno", "Giorno & Bucciarati") =
// samo ti heroji; trait s popisa (data/traits.json) = heroj boje karte koji ima taj trait, sam ili
// kroz Evolution kartu u decku. Sve ostalo je nevažeće. Usporedba bez velikih slova i rubnih razmaka.
// Isto pravilo ima igra (game/rules/first_tag.gd); zajednički testovi: game/tests/fixtures/first_tag_cases.json.
// Bez I/O, isto za app i testove.

export const GENERAL = 'general';
export const HEROES = 'heroes';
export const TRAIT = 'trait';
export const INVALID = 'invalid';
export const HERO_JOIN = '&';

export const norm = s => String(s ?? '').trim().toLowerCase();

// Popis traitova: [{ name, description }] (data/traits.json) ili samo imena.
export function traitNames(traits) {
  return (traits ?? []).map(t => (typeof t === 'string' ? t : t?.name)).filter(Boolean);
}

// Imena po kojima se heroj prepoznaje u prvom tagu: ime s karte i aliasi (polje aliases).
export function heroAliases(hero) {
  return [...new Set([hero.name, ...(hero.aliases ?? [])].map(norm).filter(Boolean))];
}

const heroesOf = db => db.cards.filter(c => c.type === 'Hero' && !c.deleted);

// Što prvi tag znači: { kind: general | heroes | trait | invalid, tag, heroes?: [ime], trait?: ime }.
export function firstTag(db, card, traits) {
  const tag = String(card.traits?.[0] ?? '').trim();
  if (!tag) return { kind: INVALID, tag };
  if (norm(tag) === GENERAL) return { kind: GENERAL, tag };
  const parts = tag.split(HERO_JOIN).map(norm).filter(Boolean);
  const heroes = heroesOf(db);
  const named = parts.map(p => heroes.find(h => heroAliases(h).includes(p)));
  if (parts.length && named.every(Boolean)) return { kind: HEROES, tag, heroes: [...new Set(named.map(h => h.name))] };
  const trait = traitNames(traits).find(t => norm(t) === norm(tag));
  if (trait) return { kind: TRAIT, tag, trait };
  return { kind: INVALID, tag };
}

// Ima li karta (heroj ili Evolution) trait: neki tag točno jednak imenu traita.
export function hasTrait(card, trait) {
  return (card?.traits ?? []).some(t => norm(t) === norm(trait));
}

// Kratka oznaka za deck builder: "General", "Signature: Giorno", "Trait: Stand", "Invalid: Hakki".
export function tagLabel(kind) {
  if (kind.kind === GENERAL) return 'General';
  if (kind.kind === HEROES) return `Signature: ${kind.heroes.join(' & ')}`;
  if (kind.kind === TRAIT) return `Trait: ${kind.trait}`;
  return kind.tag ? `Invalid: ${kind.tag}` : 'Invalid: no tag';
}

// Smije li karta u deck s ovim herojima (id-evi) i ovim Evolution kartama u decku (id-evi).
// { ok, why, needs: [id Evolution karata koje bi je otključale] }.
export function deckVerdict(db, traits, card, heroIds, evolutionIds = []) {
  const ids = new Map(db.cards.map(c => [c.id, c]));
  const heroes = heroIds.map(id => ids.get(id)).filter(Boolean);
  const evos = evolutionIds.map(id => ids.get(id)).filter(Boolean);
  const colors = new Set(heroes.map(h => h.color));
  if (card.type === 'Evolution') {
    return heroes.some(h => h.name === card.hero)
      ? { ok: true, why: '', needs: [] }
      : { ok: false, why: `Evolution for a hero who isn't in the deck`, needs: [] };
  }
  if (!colors.has(card.color)) return { ok: false, why: `color ${card.color} is not a color of the chosen heroes`, needs: [] };
  const kind = firstTag(db, card, traits);
  const same = heroes.filter(h => h.color === card.color);
  if (kind.kind === GENERAL) return { ok: true, why: '', needs: [] };
  if (kind.kind === HEROES) {
    return same.some(h => kind.heroes.includes(h.name))
      ? { ok: true, why: '', needs: [] }
      : { ok: false, why: `only for ${kind.heroes.join(' or ')}`, needs: [] };
  }
  if (kind.kind === TRAIT) {
    if (same.some(h => hasTrait(h, kind.trait))) return { ok: true, why: '', needs: [] };
    const names = new Set(same.map(h => h.name));
    if (evos.some(e => names.has(e.hero) && hasTrait(e, kind.trait))) return { ok: true, why: '', needs: [] };
    const needs = db.cards.filter(e => !e.deleted && e.type === 'Evolution' && names.has(e.hero) && hasTrait(e, kind.trait));
    if (needs.length) return { ok: false, why: `Requires ${needs.map(e => e.name).join(' or ')}`, needs: needs.map(e => e.id) };
    return { ok: false, why: `needs a ${card.color} hero with ${kind.trait}`, needs: [] };
  }
  return { ok: false, why: kind.tag ? `first tag "${kind.tag}" is not General, a hero or a known trait` : 'the card has no tags', needs: [] };
}
