// Pravilo prvog taga (odluka 2026-10-26): prvi tag karte kaže tko je smije u deck
// (i u igri): General = svaki heroj boje karte; alias heroja ("Giorno", "Giorno & Bucciarati") =
// samo ti heroji (ime iza "&" koje još nije heroj se preskače: "Shanks & Roger" je Shanksova dok
// Roger ne dođe); tag koji nosi neki heroj ili Evolution (Marko 2026-11-16: bilo koji, popisa traitova više
// nema u pravilu; data/traits.json su samo opisi) = heroj boje karte koji ima taj tag, sam ili
// kroz Evolution kartu u decku. Sve ostalo je nevažeće. Usporedba bez velikih slova i rubnih razmaka.
// U kodu se takav tag i dalje zove trait (kind "trait", polje traits).
// "&" spaja i traitove, i heroje s traitovima (Marko 2026-11-15): "Mage & Brave Hero" = heroj s bilo kojim od ta
// dva traita, "Dai & Mage" = Dai ili heroj s traitom Mage. Svaki dio je prvo heroj, inače trait; dio koji nije
// ni jedno ni drugo se preskače dok drugi dio vrijedi.
// Isto pravilo ima igra (game/rules/first_tag.gd); zajednički testovi: game/tests/fixtures/first_tag_cases.json.
// Bez I/O, isto za app i testove.

export const GENERAL = 'general';
export const HEROES = 'heroes';
export const TRAIT = 'trait';
// Heroes and traits in one tag ("Dai & Mage").
export const MIXED = 'mixed';
export const INVALID = 'invalid';
export const HERO_JOIN = '&';

export const norm = s => String(s ?? '').trim().toLowerCase();

// Riječi pravila (Marko 2026-11-15, DQ "Hero" kao tag): tag ne smije biti nijedna od njih, ni u množini, inače
// "Hero" tag i "Hero" vrsta karte čitaju se isto. Cijeli tag, ne dio: "Brave Hero" je u redu. General je riječ
// prvog taga i nije ovdje.
export const RULE_WORDS = [
  'Hero', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage', 'Core', 'Combo', 'Token', 'Card',
  'Deck', 'Hand', 'Graveyard', 'Energy', 'Power', 'HP', 'DMG', 'Damage', 'Range', 'Knockback', 'Ring-out',
  'Battle', 'Phase', 'Turn', 'Start', 'Preroll', 'Roll', 'Postroll', 'End', 'Opponent', 'Player', 'Ally',
  'Wall', 'Terrain', 'Bonus', 'Space', 'Hex', 'Ball',
];
const RULE_SET = new Map(RULE_WORDS.map(w => [norm(w), w]));

// The rule word a tag is ("Heroes" → "Hero"), or null; each part of "Mage & Hero" counts on its own.
export function ruleWord(tag) {
  for (const part of String(tag ?? '').split('&')) {
    const w = norm(part);
    if (!w) continue;
    for (const f of [w, w.replace(/s$/, ''), w.replace(/es$/, '')]) if (RULE_SET.has(f)) return RULE_SET.get(f);
  }
  return null;
}

// Opisi tagova: [{ name, description }] (data/traits.json) ili samo imena. Pravilo ih ne čita.
export function traitNames(traits) {
  return (traits ?? []).map(t => (typeof t === 'string' ? t : t?.name)).filter(Boolean);
}

// Imena po kojima se heroj prepoznaje u prvom tagu: ime s karte i aliasi (polje aliases).
export function heroAliases(hero) {
  return [...new Set([hero.name, ...(hero.aliases ?? [])].map(norm).filter(Boolean))];
}

const heroesOf = db => db.cards.filter(c => c.type === 'Hero' && !c.deleted);

// The tag a hero or an Evolution carries that `normed` names, as written on the first card that has it (in the
// order of the cards); null if nobody carries it. Same pick as FirstTag._trait_named in the game.
export function carriedTag(db, normed) {
  for (const c of db.cards) {
    if (c.deleted || (c.type !== 'Hero' && c.type !== 'Evolution')) continue;
    for (const t of c.traits ?? []) if (norm(t) === normed && normed) return String(t).trim();
  }
  return null;
}

// Što prvi tag znači: { kind, tag, heroes: [ime], traits: [ime], unknown: [dio], trait? }.
// kind: general | heroes (samo heroji) | trait (samo traitovi, jedan ili više; trait je prvi) | mixed (oboje) |
// invalid. Zadovoljava ga heroj naveden u heroes ili heroj s nekim od traits.
export function firstTag(db, card) {
  const tag = String(card.traits?.[0] ?? '').trim();
  if (!tag) return { kind: INVALID, tag };
  if (norm(tag) === GENERAL) return { kind: GENERAL, tag };
  const parts = tag.split(HERO_JOIN).map(norm).filter(Boolean);
  const heroes = heroesOf(db);
  const named = [];
  const got = [];
  const unknown = [];
  for (const p of parts) {
    const hero = heroes.find(h => heroAliases(h).includes(p));
    if (hero) { if (!named.includes(hero.name)) named.push(hero.name); continue; }
    const t = carriedTag(db, p);
    if (!t) unknown.push(p);
    else if (!got.includes(t)) got.push(t);
  }
  // "Shanks & Roger": dio koji još nije ni heroj ni trait se preskače, pa je karta Shanksova dok Roger ne dođe
  // (tagWarnings ga i dalje navede). Tag bez "&" mora biti heroj ili trait kakav jest.
  if ((named.length || got.length) && (!unknown.length || parts.length > 1)) {
    const kind = !got.length ? HEROES : !named.length ? TRAIT : MIXED;
    return { kind, tag, heroes: named, traits: got, unknown, ...(kind === TRAIT ? { trait: got[0] } : {}) };
  }
  // A tag whose own name holds an "&".
  const whole = carriedTag(db, norm(tag));
  if (whole) return { kind: TRAIT, tag, heroes: [], traits: [whole], unknown: [], trait: whole };
  return { kind: INVALID, tag };
}

// Ima li karta neki od traitova.
export const hasAnyTrait = (card, traits) => (traits ?? []).some(t => hasTrait(card, t));

// Who the tag is for, for a refusal (the same words as FirstTag._who in the game).
function whoFor(card, kind) {
  const withT = isColorless(card) ? `a hero with ${kind.traits.join(' or ')}` : `a ${card.color} hero with ${kind.traits.join(' or ')}`;
  if (!kind.traits.length) return `only for ${kind.heroes.join(' or ')}`;
  if (!kind.heroes.length) return `needs ${withT}`;
  return `only for ${kind.heroes.join(' or ')}, or ${withT}`;
}

// Ima li karta (heroj ili Evolution) trait: neki tag točno jednak imenu traita.
export function hasTrait(card, trait) {
  return (card?.traits ?? []).some(t => norm(t) === norm(trait));
}

// Kratka oznaka za deck builder: "General", "Signature: Giorno", "Tag: Stand", "Invalid: Hakki".
export function tagLabel(kind) {
  if (kind.kind === GENERAL) return 'General';
  if (kind.kind === HEROES) return `Signature: ${kind.heroes.join(' & ')}`;
  if (kind.kind === TRAIT) return `Tag: ${kind.traits.join(' or ')}`;
  if (kind.kind === MIXED) return `Signature: ${kind.heroes.join(' & ')}, or tag ${kind.traits.join(' or ')}`;
  return kind.tag ? `Invalid: ${kind.tag}` : 'Invalid: no tag';
}

// Colorless karta (color "None", 2026-11-01): generička, igra je heroj bilo koje boje; prvi tag i dalje vrijedi.
// bonusColors: boje za koje ima bonus (najviše 2) kad je heroj za kojeg se igra te boje.
export const COLORLESS = 'None';
export const isColorless = card => card?.color === COLORLESS;

// Tagovi koje karta daje herojima u partiji ("The equipped Hero gains {Mage}", "Your Heroes gain {Brave Hero}"), isto kao
// FirstTag.tags_given u igri: iz fx-a (GAIN_TAG), a bez njega iz teksta.
export function tagsGiven(card) {
  const out = [];
  for (const m of String(card?.fx ?? '').matchAll(/\bGAIN_TAG\s+\S+\s+\{([^}]+)\}/g)) out.push(m[1].trim());
  if (!out.length) for (const m of String(card?.text ?? '').matchAll(/\bgains?\s+\{([^}]+)\}/gi)) out.push(m[1].trim());
  return [...new Set(out)];
}

const givesAny = (card, traits) => tagsGiven(card).some(g => traits.some(t => norm(t) === norm(g)));

// Smije li karta u deck s ovim herojima (id-evi) i ovim Evolution kartama u decku (id-evi). Uz Evolution karte popis smije
// imati i karte koje daju tag u partiji (Marko 2026-11-22): s takvom kartom u decku smiju i karte s tim prvim tagom.
// { ok, why, needs: [id karata koje bi je otključale: Evolution, pa karte koje daju tag] }.
export function deckVerdict(db, card, heroIds, evolutionIds = []) {
  // A token is made by another card in play (GDD 10, 2026-11-14): never in a deck. Same rule as FirstTag.deck_verdict.
  if (card.token) return { ok: false, why: 'a token is never in a deck', needs: [] };
  const ids = new Map(db.cards.map(c => [c.id, c]));
  const heroes = heroIds.map(id => ids.get(id)).filter(Boolean);
  const evos = evolutionIds.map(id => ids.get(id)).filter(Boolean);
  const colors = new Set(heroes.map(h => h.color));
  if (card.type === 'Evolution') {
    return heroes.some(h => h.name === card.hero)
      ? { ok: true, why: '', needs: [] }
      : { ok: false, why: `Evolution for a hero who isn't in the deck`, needs: [] };
  }
  const colorless = isColorless(card);
  if (!colorless && !colors.has(card.color)) return { ok: false, why: `color ${card.color} is not a color of the chosen heroes`, needs: [] };
  const kind = firstTag(db, card);
  const same = colorless ? heroes : heroes.filter(h => h.color === card.color);
  if (kind.kind === GENERAL) return { ok: true, why: '', needs: [] };
  if (kind.kind === HEROES || kind.kind === TRAIT || kind.kind === MIXED) {
    // A hero named in the tag, or one that carries one of its traits (on its card or on an Evolution in the deck).
    if (same.some(h => kind.heroes.includes(h.name))) return { ok: true, why: '', needs: [] };
    if (same.some(h => hasAnyTrait(h, kind.traits))) return { ok: true, why: '', needs: [] };
    const names = new Set(same.map(h => h.name));
    if (evos.some(e => e.type === 'Evolution' && names.has(e.hero) && hasAnyTrait(e, kind.traits))) return { ok: true, why: '', needs: [] };
    if (evos.some(e => e.type !== 'Evolution' && e.id !== card.id && givesAny(e, kind.traits))) return { ok: true, why: '', needs: [] };
    const needs = db.cards.filter(e => !e.deleted && e.type === 'Evolution' && names.has(e.hero) && hasAnyTrait(e, kind.traits));
    // Karte koje daju tag, samo one koje i same smiju u ovaj deck.
    needs.push(...db.cards.filter(g => !g.deleted && !g.token && g.id !== card.id && ['Action', 'Equipment', 'Assist'].includes(g.type) &&
      givesAny(g, kind.traits) && deckVerdict(db, g, heroIds).ok));
    if (needs.length) return { ok: false, why: `Requires ${needs.map(e => e.name).join(' or ')}`, needs: needs.map(e => e.id) };
    return { ok: false, why: whoFor(card, kind), needs: [] };
  }
  return { ok: false, why: kind.tag ? `first tag "${kind.tag}" is not General, a hero or a tag a hero carries` : 'the card has no tags', needs: [] };
}
