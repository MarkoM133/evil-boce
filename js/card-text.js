// Tekst karte u editoru i u bazi. Editor pokazuje tokene kao mockup ([HP], [PWR], [DMG], [RNG], [KB], [EN];
// [RNG] na početku = efekt u rangeu), a cards.json i igra čitaju riječi ("3 HP", "+2000 Power", "[Range] ").
// Faza, Once Per Turn i Range se biraju prekidačima; tekst ih drži na početku ("Battle Phase Once Per Turn: …").

const WORD = { HP: 'HP', DMG: 'DMG', PWR: 'Power', RNG: 'Range', KB: 'Knockback', EN: 'Energy' };
const TOKEN = { HP: 'HP', DMG: 'DMG', Power: 'PWR', Range: 'RNG', Knockback: 'KB', Energy: 'EN' };
export const PHASES = ['Start', 'Preroll', 'Roll', 'Postroll', 'Battle', 'End'];
const HEAD_RE = /^(\[(?:RNG|Range)\]\s*)?(?:(Start|Preroll|Roll|Postroll|Battle|End)(?: Phase)?(\s+Once Per Turn)?\s*:\s*)?/i;

// Riječi (baza) → tokeni (editor). Riječ stata iza broja se lijepi uz broj ("2 DMG" → "2[DMG]"),
// iza more/less ostaje razmak ("more HP" → "more [HP]"), "[Range] " na početku je "[RNG]".
export function toTokens(text) {
  return (text ?? '')
    .replace(/^\[Range\]\s*/gim, '[RNG]')
    .replace(/(\d)\s?(HP|DMG|Power|Range|Knockback|Energy)\b/g, (_, d, w) => `${d}[${TOKEN[w]}]`)
    .replace(/\b(more|less)\s(HP|DMG|Power|Range|Knockback|Energy)\b/g, (_, m, w) => `${m} [${TOKEN[w]}]`)
    // Energy je token i bez broja ("charged Energy" → "charged [EN]"), kao što je na karti dijamant.
    .replace(/\bEnergy\b/g, '[EN]');
}

// Tokeni (editor) → riječi (baza): "2[DMG]" → "2 DMG", "more [HP]" → "more HP", "[RNG]" na početku → "[Range] ".
export function toWords(text) {
  return (text ?? '')
    .replace(/^\[RNG\]\s*/gim, '[Range] ')
    .replace(/\[(HP|DMG|PWR|RNG|KB|EN)\]/g, (_, k, off, s) => {
      const prev = s[off - 1];
      return (prev && !/\s/.test(prev) ? ' ' : '') + WORD[k];
    })
    .replace(/\*\*/g, '');
}

// Početak teksta: { range, phase, once, rest } (za prekidače faze, Once per turn i Range).
export function head(text) {
  const m = HEAD_RE.exec(text ?? '');
  const phase = m[2] ? PHASES.find(p => p.toLowerCase() === m[2].toLowerCase()) : null;
  return { range: !!m[1], phase, once: !!m[3], rest: (text ?? '').slice(m[0].length) };
}

export function withHead(text, { range, phase, once }) {
  const { rest } = head(text);
  const p = phase ? `${phase} Phase${once ? ' Once Per Turn' : ''}: ` : '';
  return `${range ? '[RNG]' : ''}${p}${rest}`;
}

// Više efekata: prekidači faze rade na efektu u kojem je kursor (njegov prvi redak; natuknice "- " pripadaju
// retku iznad). Vraća { start, end } tog retka i njegov početak (range, phase, once).
export function headAt(text, caret) {
  const lines = (text ?? '').split('\n');
  let pos = 0;
  let idx = 0;
  for (let i = 0; i < lines.length; i++) {
    if (caret <= pos + lines[i].length) { idx = i; break; }
    pos += lines[i].length + 1;
    idx = i;
  }
  while (idx > 0 && /^\s*[-•]/.test(lines[idx])) idx--;
  const start = lines.slice(0, idx).reduce((n, l) => n + l.length + 1, 0);
  return { start, end: start + lines[idx].length, ...head(lines[idx]) };
}

export function withHeadAt(text, caret, patch) {
  const t = text ?? '';
  const at = headAt(t, caret);
  const line = t.slice(at.start, at.end);
  const next = withHead(line, { ...head(line), ...patch });
  return { text: t.slice(0, at.start) + next + t.slice(at.end), caret: at.start + next.length - head(next).rest.length };
}

// Stage: red "Terrain: X" piše editor ispod teksta; u polju ga nema.
export function stripTerrain(text) {
  return (text ?? '').replace(/\n?^Terrain:.*$/gim, '').trimEnd();
}

export function withTerrain(text, terrain) {
  const t = stripTerrain(text);
  return terrain ? `${t}${t ? '\n' : ''}Terrain: ${terrain}` : t;
}

// Core: efekt "+2000[PWR]" je bonus { pwr: 2000 }; slika se crta iz njega.
const BONUS_KEY = { PWR: 'pwr', DMG: 'dmg', KB: 'kb', HP: 'hp', RNG: 'rng' };
const KEY_TOKEN = { pwr: 'PWR', dmg: 'DMG', kb: 'KB', hp: 'HP', rng: 'RNG' };

export function coreBonus(effect) {
  const bonus = {};
  for (const m of (effect ?? '').matchAll(/(?<![\w.])([+\-−]?\d+)\s*\[(PWR|DMG|KB|HP|RNG)\]/g)) bonus[BONUS_KEY[m[2]]] = Number(m[1].replace('−', '-'));
  return bonus;
}

export function coreEffect(bonus) {
  return Object.entries(bonus ?? {}).filter(([, v]) => v).map(([k, v]) => `${v > 0 ? '+' : ''}${v}[${KEY_TOKEN[k]}]`).join(' ');
}
