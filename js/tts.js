// Podaci za TTS (Sync karata): od cards.json napravi karte i heroje u obliku koji global.lua samo primijeni.
// Bez I/O; server (GET /api/tts) doda putanju foldera, Steam URL-ove i biblioteku bakugana.

// Poleđina svih karata (Steam, već u saveu).
export const CARD_BACK_URL = 'https://steamusercontent-a.akamaihd.net/ugc/14052693484240953624/34A79A178076BF7407A775C3D4CFC779E89ABBFA/';

const STAT_ORDER = [['hp', 'HP'], ['dmg', 'DMG'], ['pwr', 'Power'], ['rng', 'Range'], ['kb', 'Knockback']];

// Opis karte u TTS-u, isti oblik koji je pisao cards_import.py (global.lua iz njega čita cost i bonuse):
//   Action  ·  Cost 1  ·  OP1-008
//   Power +2000
//   Luffy/Devil Fruit
//
//   Battle Phase: ...
export function ttsDescription(card) {
  const head = [card.type, card.cost !== undefined ? `Cost ${card.cost}` : null, card.evo !== undefined ? `Evo ${card.evo}` : null, card.id]
    .filter(x => x !== null && x !== undefined).join('  ·  ');
  const lines = [head];
  const stats = card.stats
    ? STAT_ORDER.filter(([k]) => card.stats[k] !== undefined).map(([k, label]) => `${label} ${card.stats[k]}`)
    : STAT_ORDER.flatMap(([k, label]) => [
        ...(card.bonus?.[k] !== undefined ? [`${label} ${card.bonus[k] > 0 ? '+' : ''}${card.bonus[k]}`] : []),
        ...(card.values?.[k] !== undefined ? [`${label} ${card.values[k]}`] : []),
      ]);
  if (stats.length) lines.push(stats.join('  '));
  if (card.traits?.length) lines.push(card.traits.join('/'));
  if (card.text) lines.push('', card.text);
  return lines.join('\n');
}

// Ime karte u TTS-u. Evolution je nekad imala dodatak " (Evolution)" jer se zvala kao heroj ("Luffy");
// sad se zove "Luffy, Gear Second", pa dodatak ne treba (heroj i bakugan se vežu po točnom imenu).
export function ttsNickname(card) {
  return card.name;
}

// Slika iz foldera: Steam URL ako je već dignut (Cloud Manager), inače lokalna putanja (pa je Upload digne).
export function assetUrl(key, relPath, { steam = {}, drivePath }) {
  if (steam[key]) return steam[key];
  return `file:///${drivePath.replace(/\\/g, '/').replace(/\/$/, '')}/data/${relPath}`;
}

// Ključevi u steam-urls.json: slika karte "OP1-008.a1b2c3d4", sprite "sprite:OP1-001.hash", tekstura bakugana "bakugan:dragonoid".
export const imageKey = card => `${card.id}.${card.imageHash}`;
export const spriteKey = card => `sprite:${card.id}.${card.spriteHash}`;
export const bakuganKey = shape => `bakugan:${shape}`;

const GAME_COLORS = { Cyan: '#00ffff', Yellow: '#ffff00', Purple: '#ff00ff', Red: '#ff0000', Blue: '#0000ff', Green: '#00ff00' };

// Obojana tekstura bakugana: siva tekstura oblika puta glavna boja, detalji drugom bojom, oči originalne;
// upečena u file (TTS ne boji dijelove modela s teksturom, pa ColorDiffuse ne pomaže).
// Isti oblik istih boja dijeli file: data/bakugani/boje/<oblik>-<glavna>-<druga>.jpg (bez druge boje su iste).
export function bakuganTextureId(card) {
  if (!card.bakuganShape) return null;
  const hex = c => c.replace('#', '').toLowerCase();
  const main = card.bakuganColor ?? GAME_COLORS[card.color] ?? '#ffffff';
  return `${card.bakuganShape}-${hex(main)}-${hex(card.bakuganColor2 ?? main)}`;
}

// Sve što TTS treba: karte (master kopije) i heroji (statsi, bakugan, sprite).
// opts: { steam: {key: url}, drivePath: 'C:/…/EvilBoce', bakugani: [{id, name, meshUrl}] }
export function ttsPayload(db, opts) {
  const cards = [...db.cards].sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  const lib = new Map((opts.bakugani ?? []).map(b => [b.id, b]));
  return {
    version: db.version,
    back: CARD_BACK_URL,
    cards: cards.map((c, i) => ({
      id: c.id,
      deck: 1000 + i, // broj CustomDecka u TTS-u; jedinstven po karti, svi klonovi ga dijele
      nickname: ttsNickname(c),
      description: ttsDescription(c),
      type: c.type,
      face: c.image ? assetUrl(imageKey(c), c.image, opts) : null,
      key: c.image ? imageKey(c) : null,
      rev: c.rev ?? 0,
      deleted: !!c.deleted,
      sprite: c.sprite ? assetUrl(spriteKey(c), c.sprite, opts) : null,
      spriteKey: c.sprite ? spriteKey(c) : null,
    })),
    heroes: cards.filter(c => c.type === 'Character' && !c.deleted).map(c => {
      const shape = lib.get(c.bakuganShape);
      return {
        id: c.id,
        name: c.name,
        stats: {
          max: c.stats?.hp ?? 8,
          dmg: c.stats?.dmg ?? 0,
          pwr: Math.round((c.stats?.pwr ?? 0) / 1000),
          rng: c.stats?.rng ?? 0,
          kb: c.stats?.kb ?? 0,
          wt: c.wt ?? 2,
        },
        bakugan: shape ? {
          shape: shape.id,
          name: shape.name,
          mesh: shape.meshUrl,
          texture: assetUrl(bakuganKey(bakuganTextureId(c)), `bakugani/boje/${bakuganTextureId(c)}.jpg`, opts),
          textureKey: bakuganKey(bakuganTextureId(c)),
          color: [1, 1, 1],
        } : null,
        sprite: c.sprite ? assetUrl(spriteKey(c), c.sprite, opts) : null,
        spriteKey: c.sprite ? spriteKey(c) : null,
      };
    }),
  };
}

// Steam URL-ovi koje je TTS poslao nazad: samo ključevi koje poznajemo i samo Steam adrese.
export function mergeSteamUrls(current, incoming) {
  const out = { ...current };
  let added = 0;
  for (const [k, url] of Object.entries(incoming ?? {})) {
    if (!/^(?:[A-Za-z0-9]+-\d{3}\.[0-9a-f]{8}|sprite:[A-Za-z0-9]+-\d{3}\.[0-9a-f]{8}|bakugan:[a-z0-9-]+)$/.test(k)) continue;
    if (typeof url !== 'string' || !/^https:\/\/steamusercontent[-a-z.]*\.(?:akamaihd\.net|com)\//.test(url)) continue;
    if (out[k] !== url) { out[k] = url; added++; }
  }
  return { steam: out, added };
}
