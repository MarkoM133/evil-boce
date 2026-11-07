// Dizajn paket za dizajnerski chat (Marko 2026-11-07): docs/private/dizajn-paket.md.
// Karte (po setu i heroju) i brojke za balans generiraju se iz objavljene baze (data/cards.json u
// zajedničkom folderu); sažetak pravila piše se ručno u samoj datoteci između oznaka RUCNO i ostaje
// pri svakom osvježavanju. Pravila i karte nikad ne idu u git: skripta ih samo čita i piše u docs/private.
// Pokreni nakon svake Objave i na kraju sesije: npm run design-pack
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { firstTag, GENERAL, HEROES, TRAIT, heroAliases, norm } from '../js/tags.js';
import { combosOf, isCombo } from '../js/combo.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const MANUAL_START = '<!-- RUCNO:POCETAK (ovaj dio piše se ručno; skripta ga ne dira) -->';
export const MANUAL_END = '<!-- RUCNO:KRAJ -->';
const STAT_KEYS = [['hp', 'HP'], ['dmg', 'DMG'], ['pwr', 'PWR'], ['rng', 'RNG'], ['kb', 'KB']];
const BONUS_NAMES = { pwr: 'Power', dmg: 'DMG', hp: 'HP', rng: 'Range', kb: 'Knockback' };

const colorOf = c => (c.color === 'None' ? `Colorless${c.bonusColors?.length ? ` (bonus: ${c.bonusColors.join(' / ')})` : ''}` : c.color);
const statLine = s => STAT_KEYS.map(([k, l]) => `${l} ${s?.[k] ?? '–'}`).join(' · ');
const bonusLine = b => Object.entries(b ?? {}).filter(([, v]) => v).map(([k, v]) => `${v > 0 ? '+' : ''}${v} ${BONUS_NAMES[k] ?? k}`).join(', ');
const setOf = c => String(c.id).split('-')[0];

// Tekst karte: ručni prijelomi unutar rečenice postaju razmak, novi efekt (iza . ili :) novi redak.
export function cardText(text) {
  const lines = String(text ?? '').split('\n').map(l => l.trim()).filter(Boolean);
  let out = '';
  for (const l of lines) out += !out ? l : /[.:!?]$/.test(out) ? `\n${l}` : ` ${l}`;
  return out;
}

export function cardBlock(c, cards = []) {
  const head = [`**${c.id} ${c.name}**`, c.type];
  if (c.color) head.push(colorOf(c));
  if (c.type === 'Evolution') head.push(`razina ${c.evo ?? 1}`, `baza ${c.hero ?? '?'}`);
  if (c.cost != null && c.type !== 'Hero') head.push(`cost ${c.cost}`);
  const rows = [`- ${head.join(' · ')}`];
  if (c.type === 'Hero' || c.type === 'Evolution') rows.push(`  Statsi: ${statLine(c.stats)}${c.wt ? ` · WT ${c.wt}` : ''}`);
  const bonus = bonusLine(c.bonus);
  if (bonus) rows.push(`  Bonus kvadratići: ${bonus}`);
  const tags = c.traits ?? [];
  if (tags.length) rows.push(`  Tagovi: ${tags.map((t, i) => (i === 0 ? `**${t}** (prvi)` : t)).join(' / ')}`);
  if (c.aliases?.length) rows.push(`  Aliasi: ${c.aliases.join(', ')}`);
  if (c.abilityNames?.filter(Boolean).length) rows.push(`  Ability: ${c.abilityNames.filter(Boolean).join(' · ')}`);
  if (c.terrain) rows.push(`  Teren: ${c.terrain}`);
  if (isCombo(c)) {
    const names = (c.ingredients ?? []).map(id => { const x = cards.find(k => k.id === id); return x ? `${x.name} (${id})` : id; });
    rows.push(`  Sastojci: ${names.join(' + ')} · dodatno +${c.extraCost ?? 0} energije · uvedeno u ${c.introducedIn || '?'}`);
  }
  const inCombos = combosOf(cards, c.id);
  if (inCombos.length) rows.push(`  Combo (iskra uz kod): ${inCombos.map(x => `${x.id} ${x.name}`).join(', ')}`);
  // A stage's terrain line is the Teren field above (the card prints it under the text).
  const text = cardText(c.type === 'Stage' ? String(c.text ?? '').replace(/^s*Terrain:.*$/gim, '') : c.text);
  if (text) rows.push(...text.split('\n').map((l, i) => `  ${i ? '' : 'Tekst: '}${l}`.replace(/^ {2}(?!Tekst)/, '        ')));
  return rows.join('\n');
}

// Grupe jednog seta: heroji (s evolucijama i kartama čiji ih prvi tag imenuje), pa trait karte, pa General.
export function groupSet(db, traits, setCards) {
  const heroes = setCards.filter(c => c.type === 'Hero').sort((a, b) => a.id.localeCompare(b.id));
  const used = new Set();
  const groups = [];
  for (const h of heroes) {
    const own = [h];
    used.add(h.id);
    for (const e of db.cards.filter(c => c.type === 'Evolution' && !c.deleted && norm(c.hero) === norm(h.name))) { own.push(e); used.add(e.id); }
    for (const c of setCards) {
      if (used.has(c.id) || c.type === 'Hero' || c.type === 'Evolution') continue;
      const k = firstTag(db, c, traits);
      if (k.kind === HEROES && k.heroes[0] === h.name) { own.push(c); used.add(c.id); }
    }
    groups.push({ title: `${h.name} (${h.color})`, cards: own });
  }
  const rest = setCards.filter(c => !used.has(c.id));
  const byKey = new Map();
  for (const c of rest) {
    const k = firstTag(db, c, traits);
    const key = k.kind === TRAIT ? `Trait ${k.trait}` : k.kind === GENERAL ? 'General' : k.kind === HEROES ? `${k.heroes.join(' & ')}` : `Nevažeći prvi tag (${k.tag || 'bez taga'})`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(c);
  }
  for (const [title, cards] of [...byKey.entries()].sort((a, b) => a[0].localeCompare(b[0]))) groups.push({ title, cards });
  return groups;
}

const avg = xs => (xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : 0);
const fmt = x => (Number.isInteger(x) ? String(x) : x.toFixed(1));

export function balanceSection(db, traits, sets = []) {
  const live = db.cards.filter(c => !c.deleted);
  const order = c => { const i = sets.findIndex(x => x.code === setOf(c)); return i < 0 ? 99 : i; };
  const out = [];
  const heroes = live.filter(c => c.type === 'Hero');
  const statTable = (list, extra = []) => {
    const rows = ['| Karta | ' + [...extra.map(e => e[0]), ...STAT_KEYS.map(s => s[1]), 'WT'].join(' | ') + ' |', '|' + '---|'.repeat(extra.length + STAT_KEYS.length + 2)];
    for (const c of list) rows.push(`| ${c.name} | ${[...extra.map(e => e[1](c)), ...STAT_KEYS.map(([k]) => c.stats?.[k] ?? '–'), c.wt ?? '–'].join(' | ')} |`);
    const nums = k => list.map(c => Number(c.stats?.[k])).filter(Number.isFinite);
    rows.push(`| *raspon (prosjek)* | ${[...extra.map(() => ''), ...STAT_KEYS.map(([k]) => { const n = nums(k); return n.length ? `${Math.min(...n)}–${Math.max(...n)} (${fmt(avg(n))})` : '–'; }), ''].join(' | ')} |`);
    return rows.join('\n');
  };
  out.push('### Heroji', '', statTable(heroes.sort((a, b) => order(a) - order(b) || a.id.localeCompare(b.id, undefined, { numeric: true })), [['Boja', c => c.color]]), '');
  const evos = live.filter(c => c.type === 'Evolution');
  if (evos.length) out.push('### Evolucije', '', statTable(evos, [['Baza', c => c.hero ?? '?'], ['Razina', c => c.evo ?? 1], ['Cost', c => c.cost ?? '–']]), '');
  // Koliko karata ima koji heroj (prvi tag ga imenuje); cilj je 8 po heroju.
  out.push('### Karte po heroju (prvi tag imenuje heroja; cilj 8)', '', '| Heroj | Boja | Svoje karte | Evolucije |', '|---|---|---|---|');
  for (const h of heroes) {
    const own = live.filter(c => !['Hero', 'Evolution', 'Stage', 'Core'].includes(c.type) && firstTag(db, c, traits).kind === HEROES && firstTag(db, c, traits).heroes.includes(h.name)).length;
    const ev = evos.filter(e => norm(e.hero) === norm(h.name)).length;
    out.push(`| ${h.name} | ${h.color} | ${own} | ${ev} |`);
  }
  out.push('');
  // Cost i bonus kvadratići po tipu.
  const playable = live.filter(c => ['Action', 'Equipment', 'Assist'].includes(c.type));
  out.push('### Cost po tipu (Action, Equipment, Assist)', '', '| Tip | Cost 0 | 1 | 2 | 3 | 4 | 5+ | Ukupno |', '|---|---|---|---|---|---|---|---|');
  for (const t of ['Action', 'Equipment', 'Assist']) {
    const list = playable.filter(c => c.type === t);
    const at = n => list.filter(c => (n === 5 ? (c.cost ?? 0) >= 5 : (c.cost ?? 0) === n)).length;
    out.push(`| ${t} | ${[0, 1, 2, 3, 4, 5].map(at).join(' | ')} | ${list.length} |`);
  }
  out.push('', '### Bonus kvadratići po costu (karte koje ih imaju)', '', '| Cost | Karte | Prosjek Power | Prosjek DMG | Prosjek KB |', '|---|---|---|---|---|');
  const boxed = playable.filter(c => Object.values(c.bonus ?? {}).some(Boolean));
  for (const cost of [...new Set(boxed.map(c => c.cost ?? 0))].sort((a, b) => a - b)) {
    const list = boxed.filter(c => (c.cost ?? 0) === cost);
    const a = k => fmt(avg(list.map(c => Number(c.bonus?.[k] ?? 0))));
    out.push(`| ${cost} | ${list.map(c => c.name).join(', ')} | ${a('pwr')} | ${a('dmg')} | ${a('kb')} |`);
  }
  out.push('', '### Karte po boji', '', '| Boja | Action | Equipment | Assist | Evolution |', '|---|---|---|---|---|');
  for (const col of [...new Set(live.filter(c => !['Stage', 'Core', 'Hero', 'Combo'].includes(c.type)).map(c => c.color))].sort()) {
    const n = t => live.filter(c => c.type === t && c.color === col).length;
    out.push(`| ${col === 'None' ? 'Colorless' : col} | ${n('Action')} | ${n('Equipment')} | ${n('Assist')} | ${n('Evolution')} |`);
  }
  return out.join('\n');
}

export function buildPack({ db, traits, sets, gameVersion, manual, now = new Date() }) {
  const live = db.cards.filter(c => !c.deleted);
  const setName = code => sets.find(s => s.code === code)?.name ?? code;
  const parts = [
    '# Evil Boće – dizajn paket',
    '',
    `Generirano ${now.toISOString().slice(0, 10)} iz objavljene baze: karte verzija ${db.version}, ${live.length} karata, igra ${gameVersion}. Karte i brojke osvježava Claude Code (\`npm run design-pack\`) nakon svake Objave i na kraju sesije; sažetak pravila je ručni.`,
    '',
    '## 1. Pravila igre (sažetak)',
    '',
    MANUAL_START,
    manual?.trim() ? manual.trim() : '_(Sažetak pravila još nije upisan.)_',
    MANUAL_END,
    '',
    '## 2. Karte',
    '',
    'Po setu, unutar seta po heroju: heroj, njegove evolucije i karte čiji ga prvi tag imenuje; zatim karte s traitom ili General kao prvim tagom. **Podebljan tag** je prvi tag (tko kartu smije igrati). Statsi heroja su HP · DMG · PWR · RNG · KB (+ WT, težina kuglice). Bonus kvadratići su statsi koje Action daje sam od sebe kad se odigra.',
    '',
  ];
  const codes = [...new Set(live.filter(c => !['Stage', 'Core', 'Combo'].includes(c.type)).map(setOf))].sort((a, b) => (sets.findIndex(s => s.code === a) - sets.findIndex(s => s.code === b)) || a.localeCompare(b));
  for (const code of codes) {
    const setCards = live.filter(c => setOf(c) === code && !['Stage', 'Core', 'Combo'].includes(c.type)).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
    parts.push(`### Set ${code}: ${setName(code)} (${setCards.length} karata)`, '');
    for (const g of groupSet(db, traits, setCards)) parts.push(`#### ${g.title}`, '', ...g.cards.map(c => cardBlock(c, live)), '');
  }
  const stages = live.filter(c => c.type === 'Stage').sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  parts.push(`### Stageovi (${stages.length})`, '', ...stages.map(c => cardBlock(c, live)), '');
  const combos = live.filter(isCombo).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  if (combos.length) parts.push(`### Combo karte (${combos.length})`, '', 'Dvije karte (Action ili Assist) odigrane za dva tvoja heroja u istom battleu: igrač smije platiti dodatnu energiju (+X) i umjesto njih vrijedi Combo karta. Ne idu u deck ni u pakete.', '', ...combos.map(c => cardBlock(c, live)), '');
  const cores = live.filter(c => c.type === 'Core').sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  parts.push(`### Coreovi (${cores.length})`, '', ...cores.map(c => `- **${c.id} ${c.name}** · ${c.traits?.[0] ?? '?'}${bonusLine(c.bonus) ? ` · ${bonusLine(c.bonus)}` : ''}`), '');
  parts.push('## 3. Brojke za balans', '', balanceSection(db, traits, sets), '');
  return parts.join('\n');
}

// Ručni dio postojeće datoteke (između oznaka), ili prazno.
export function manualPart(existing) {
  const a = existing.indexOf(MANUAL_START);
  const z = existing.indexOf(MANUAL_END);
  return a >= 0 && z > a ? existing.slice(a + MANUAL_START.length, z) : '';
}

function main() {
  const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, 'server', 'config.local.json'), 'utf8'));
  const drive = cfg.driveFolder ?? cfg.drive;
  const read = (p, fb) => { try { return JSON.parse(fs.readFileSync(path.join(drive, p), 'utf8')); } catch { return fb; } };
  const db = read('data/cards.json', null);
  if (!db) throw new Error(`No data/cards.json in ${drive}`);
  const traits = read('data/traits.json', { traits: [] }).traits ?? [];
  const sets = read('data/sets/sets.json', { sets: [] }).sets ?? [];
  const godot = fs.readFileSync(path.join(ROOT, 'game', 'project.godot'), 'utf8');
  const gameVersion = /config\/version="([^"]+)"/.exec(godot)?.[1] ?? '?';
  const out = path.join(ROOT, 'docs', 'private', 'dizajn-paket.md');
  const manual = fs.existsSync(out) ? manualPart(fs.readFileSync(out, 'utf8')) : '';
  fs.writeFileSync(out, buildPack({ db, traits, sets, gameVersion, manual }));
  console.log(`${path.relative(ROOT, out)}: cards v${db.version}, ${db.cards.filter(c => !c.deleted).length} cards, game ${gameVersion}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
