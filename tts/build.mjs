// TTS save iz repoa: bazni save (privatni, docs/private/tts/base.json) + tts/global.lua -> "Evil Boce (dev).json" u TTS Saves.
//   npm run tts                  napravi i kopiraj u TTS Saves
//   npm run tts -- --adopt       save mijenjan u TTS-u (raspored, objekti) postaje nova baza, pa build
//   npm run tts -- --force       prepiši save u TTS-u iako je mijenjan (izmjene u TTS-u se gube)
// Raspored stola živi u bazi, kod u global.lua. Ako u TTS-u nešto pomakneš i spremiš, build to ne prepisuje
// dok ne kažeš --adopt (uzmi) ili --force (baci).
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

const ROOT = path.dirname(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')));
const PRIVATE = path.join(ROOT, 'docs', 'private', 'tts');
const BASE = path.join(PRIVATE, 'base.json');
const OUT = path.join(PRIVATE, 'out.json'); // isto što ide u TTS; na njemu se vrte testovi
const STAMP = path.join(PRIVATE, 'last-build.json');
const SAVES = process.env.TTS_SAVES ?? path.join(os.homedir(), 'Documents', 'My Games', 'Tabletop Simulator', 'Saves');
const TARGET = path.join(SAVES, 'Evil Boce (dev).json');
const SAVE_NAME = 'Evil Boće (dev)';

// Slike stola (npr. zid) idu u zajednički folder kao i slike karata, pa ih Cloud Manager "Upload All Loaded Files" digne na Steam.
const CONFIG = path.join(ROOT, 'server', 'config.local.json');
const DRIVE = fs.existsSync(CONFIG) ? JSON.parse(fs.readFileSync(CONFIG, 'utf8')).driveFolder : null;
function asset(name) {
  if (!DRIVE) throw new Error(`Nema driveFolder u ${CONFIG}.`);
  const to = path.join(DRIVE, 'tts', name);
  const from = path.join(ROOT, 'tts', 'assets', name);
  if (!fs.existsSync(to) || !fs.readFileSync(to).equals(fs.readFileSync(from))) {
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  }
  return 'file:///' + to.replace(/\\/g, '/');
}

const args = new Set(process.argv.slice(2));
const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const readStamp = () => (fs.existsSync(STAMP) ? JSON.parse(fs.readFileSync(STAMP, 'utf8')) : null);

// Save u TTS-u mijenjan nakon zadnjeg builda (ti si spremio u TTS-u)?
function changedInTts() {
  if (!fs.existsSync(TARGET)) return false;
  const stamp = readStamp();
  return !stamp || stamp.sha !== sha(fs.readFileSync(TARGET, 'utf8'));
}

if (args.has('--adopt')) {
  if (!fs.existsSync(TARGET)) throw new Error(`Nema ${TARGET}.`);
  fs.copyFileSync(BASE, path.join(PRIVATE, `base.${new Date().toISOString().replace(/[:.]/g, '-')}.json`));
  fs.copyFileSync(TARGET, BASE);
  console.log('Save iz TTS-a je nova baza (stara je spremljena pored, base.<datum>.json).');
} else if (changedInTts() && !args.has('--force')) {
  console.error(`"${TARGET}" je mijenjan u TTS-u nakon zadnjeg builda.
  npm run tts -- --adopt   uzmi izmjene iz TTS-a kao novu bazu, pa build
  npm run tts -- --force   prepiši ih`);
  process.exit(1);
}

const save = JSON.parse(fs.readFileSync(BASE, 'utf8'));
save.LuaScript = fs.readFileSync(path.join(ROOT, 'tts', 'global.lua'), 'utf8');
save.XmlUI = fs.readFileSync(path.join(ROOT, 'tts', 'ui.xml'), 'utf8');
save.SaveName = SAVE_NAME;
// GameMode je bio "Chimera Table" (mod iz kojeg je stol): TTS po njemu imenuje folder u Cloud Manageru pri Uploadu.
save.GameMode = 'EvilBoce';

// Promjene objekata, redom; svaka smije ići više puta (baza može već biti promijenjena kroz --adopt).
const steps = [
  // 2026-10-23: energy više nije hrpa karata (max = broj turna), Energy slotovi se miču.
  ['bez Energy slotova', s => { s.ObjectStates = s.ObjectStates.filter(o => !['e9e001', 'e9e002'].includes(o.GUID)); }],
  // 2026-10-23: zid nije ravni token nego kvadar (Custom Tile, Box) sa slikom zida, 2 polja dug; global.lua ga dovede
  // na točnu veličinu (fitWall). Samo dok je još token: kad je baza preuzeta nakon Steam uploada, URL ostaje Steamov.
  ['zid kao Custom Tile', s => {
    for (const o of s.ObjectStates) {
      if (o.Name !== 'Custom_Token' || !(o.Tags ?? []).includes('Wall')) continue;
      const url = asset('wall.png');
      o.Name = 'Custom_Tile';
      o.Transform = { ...o.Transform, rotX: 0, rotY: 90, rotZ: 0, scaleX: 1, scaleY: 1, scaleZ: 1 };
      o.CustomImage = { ImageURL: url, ImageSecondaryURL: url, ImageScalar: 1, WidthScale: 0, CustomTile: { Type: 0, Thickness: 0.2, Stackable: false, Stretch: true } };
    }
  }],
  // 2026-10-24: Hero i Evolution su landscape (položene); mjesto za heroja je položena karta iste veličine.
  ['mjesta za heroje položena', s => { for (const o of s.ObjectStates) if (o.Nickname === 'Hero' && (o.Tags ?? []).includes('Slot')) o.SidewaysCard = true; }],
];
for (const [name, step] of steps) {
  const before = JSON.stringify(save.ObjectStates).length;
  step(save);
  if (JSON.stringify(save.ObjectStates).length !== before) console.log(`  ${name}`);
}

const text = JSON.stringify(save, null, 2);
fs.writeFileSync(OUT, text);
fs.mkdirSync(SAVES, { recursive: true });
fs.writeFileSync(TARGET, text);
fs.writeFileSync(STAMP, JSON.stringify({ sha: sha(text), at: new Date().toISOString() }, null, 2) + '\n');
console.log(`Napravljeno: ${TARGET}
U TTS-u: Load → "${SAVE_NAME}" (ako je već otvoren, učitaj ga ponovno).`);
