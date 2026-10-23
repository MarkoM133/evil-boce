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
save.SaveName = SAVE_NAME;

const text = JSON.stringify(save, null, 2);
fs.writeFileSync(OUT, text);
fs.mkdirSync(SAVES, { recursive: true });
fs.writeFileSync(TARGET, text);
fs.writeFileSync(STAMP, JSON.stringify({ sha: sha(text), at: new Date().toISOString() }, null, 2) + '\n');
console.log(`Napravljeno: ${TARGET}
U TTS-u: Load → "${SAVE_NAME}" (ako je već otvoren, učitaj ga ponovno).`);
