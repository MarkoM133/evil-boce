// Gramatika fx redaka, ista kao u igri (game/rules/fx_effect.gd: WHENS, VERBS, parse_line, parse_action).
// Služi za provjeru prijedloga prije nego ih Card Studio ponudi: redak koji igra ne bi pročitala se ne nudi.
// Mijenja li se gramatika u igri, mijenja se i ovdje (test/fx-grammar.test.mjs drži primjere iz fx-keywords.md).

export const WHENS = ['PLAY', 'PREROLL', 'ROLL', 'POSTROLL', 'BATTLE', 'END', 'PASSIVE', 'REVEAL'];
export const CONDS = ['ACTIVATED', 'WIN', 'OPP_EQUIPPED', 'COPIES'];
export const COLORS = ['CYAN', 'YELLOW', 'PURPLE', 'RED', 'BLUE', 'GREEN'];
// Glagol -> [ima metu, najmanje dodatnih argumenata].
export const VERBS = {
  BUFF: [true, 2], DAMAGE: [true, 1], HEAL: [true, 1], MOVE: [true, 1], KNOCKBACK: [true, 1], STATUS: [true, 1],
  DAMAGE_MOD: [true, 1], REMOVE_EVO: [true, 0], WALL: [false, 0], REVEAL_CORE: [false, 0], ACTIVATE_CORE: [false, 0],
  DEACTIVATE_CORE: [true, 0], CHARGE: [true, 1], DISCHARGE: [true, 1], DRAW: [true, 1], DISCARD: [true, 1], COST: [true, 1],
  NO_CLAIM: [true, 0], ROLL_AGAIN: [false, 0], REVERSE_ROLL: [false, 0], COST_DAMAGE: [false, 1], OWN_COST: [false, 1],
  CHOOSE: [true, 0], RECYCLE: [true, 1], PICK_CORE: [false, 0], MOVE_CORE: [false, 1], TRAP_CORE: [false, 1],
  HOLD_HIT: [true, 0], FULL_HIT: [true, 0], NOOP: [false, 0], FREE_PLAY: [false, 1], SWAP: [true, 0], DUEL_TOP: [false, 2], MOVE_ID: [false, 2],
  TOKEN: [true, 1],
  // Pratilac (GDD 10, 2026-11-21): COMPANION na PLAY Assista, HIDE <domet> [energija], WANDER <n> na END.
  COMPANION: [false, 0], HIDE: [false, 1], WANDER: [false, 1],
  // DQ1 (2026-11-22): TERRAIN <ime terena> mijenja teren stagea na kojem heroj stoji.
  TERRAIN: [false, 1],
};
// TOKEN se ne stvara u End fazi (odmah bi nestao) ni pasivno (GDD 10, 2026-11-14).
export const NO_TOKEN_WHENS = ['END', 'PASSIVE'];
export const HERO_TARGETS = ['SELF', 'EQUIPPED', 'ENEMY', 'FRIENDLY', 'ALL_FRIENDLY', 'ALL_ENEMY', 'ALL_OTHER_IN_RANGE',
  'ALL_FRIENDLY_IN_RANGE', 'ALL_ENEMY_IN_RANGE', 'ALL_FRIENDLY_IN_BATTLE', 'ALL_HEROES', 'EACH_HERO', 'MOST_HP', 'MOST_PWR', 'MOST_ENERGY'];
export const PLAYER_TARGETS = ['ME', 'OPP'];
export const STATS = ['PWR', 'DMG', 'KB', 'RNG', 'HP'];

// Dijeli na `sep` izvan [...] zagrada.
function splitTop(text, sep) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of text) {
    if (ch === '[') depth++;
    else if (ch === ']') depth--;
    if (ch === sep && depth === 0) { out.push(cur); cur = ''; } else cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out;
}

// Riječi odvojene razmakom; [...] i {...} ostaju cijeli.
function tokens(text) {
  const out = [];
  let cur = '';
  let depth = 0;
  for (const ch of text) {
    if (ch === '[' || ch === '{') depth++;
    else if (ch === ']' || ch === '}') depth--;
    if (ch === ' ' && depth === 0) { if (cur) out.push(cur); cur = ''; } else cur += ch;
  }
  if (cur) out.push(cur);
  return out;
}

// Jedna akcija: '' kad je ispravna, inače zašto nije.
export function actionProblem(text) {
  const t = tokens(text);
  if (!t.length) return 'an empty action';
  const verb = t[0].toUpperCase();
  if (!(verb in VERBS)) return `"${t[0]}" is not a verb the game knows`;
  const [takesTarget, minArgs] = VERBS[verb];
  let i = 1;
  if (takesTarget) {
    const target = (t[i] ?? '').toUpperCase();
    if (!HERO_TARGETS.includes(target) && !PLAYER_TARGETS.includes(target)) return `${verb} needs a target (SELF, ENEMY, ME, OPP…), not "${t[i] ?? ''}"`;
    i++;
  }
  const args = [];
  let branches = 0;
  for (; i < t.length; i++) {
    const tok = t[i];
    if (tok.startsWith('[')) {
      for (const part of splitTop(tok.slice(1, -1), ';')) {
        const p = actionProblem(part.trim());
        if (p) return p;
      }
      branches++;
    } else args.push(tok.startsWith('{') || tok.includes(':') ? tok : tok.toUpperCase());
  }
  if (args.length < minArgs) return `${verb} needs ${minArgs} more argument${minArgs === 1 ? '' : 's'}`;
  if (verb === 'CHOOSE' && branches < 2) return 'CHOOSE needs two [ ... ] branches';
  if (verb === 'BUFF' && (!STATS.includes(args[0]) || !/^[+-]?\d+$/.test(args[1]))) return 'BUFF needs a stat (PWR, DMG, KB, RNG, HP) and a number';
  if (verb === 'TOKEN') {
    if (!PLAYER_TARGETS.includes(t[1].toUpperCase())) return 'TOKEN needs the player who gets it: ME or OPP';
    if (args.length > 1 && !/^[1-9]\d*$/.test(args[1])) return 'TOKEN takes the token card id, then how many (1 or more)';
  }
  return '';
}

// Jedan redak: '' kad ga igra pročita, inače zašto ne.
export function lineProblem(line) {
  const colon = line.indexOf(':');
  if (colon < 0) return 'no ":" between the head and the actions';
  // A {Tag} in the head (BONUS {Mage & Brave Hero}) is one word, spaces and all.
  const head = line.slice(0, colon).trim().toUpperCase().replace(/\{[^}]*\}/g, m => m.replace(/\s+/g, '_')).split(/\s+/).filter(Boolean);
  if (!head.length || !WHENS.includes(head[0])) return `"${head[0] ?? ''}" is not a WHEN (${WHENS.join(', ')})`;
  for (let i = 1; i < head.length; i++) {
    const w = head[i];
    if (['ONCE', 'OPTIONAL', 'RANGE', 'INSTEAD'].includes(w)) continue;
    if (w === 'BONUS') { if (COLORS.includes(head[i + 1]) || /^\{.+\}$/.test(head[i + 1] ?? '')) i++; continue; }
    if (w === 'IF') {
      if (!CONDS.includes(head[i + 1])) return `IF needs one of ${CONDS.join(', ')}`;
      i++;
      if (i + 1 < head.length) i++;
      continue;
    }
    return `"${w}" is not a flag the game knows`;
  }
  const body = line.slice(colon + 1).trim();
  for (const part of splitTop(body, ';')) {
    const p = actionProblem(part.trim());
    if (p) return p;
  }
  if (NO_TOKEN_WHENS.includes(head[0]) && tokenIds(line).length) return `a token is never made in ${head[0] === 'END' ? 'the End phase (it would be gone at once)' : 'a PASSIVE effect'}`;
  return '';
}

// Kodovi token karata koje fx stvara (TOKEN <ME|OPP> <kod> [n]), i unutar CHOOSE grana.
export function tokenIds(fx) {
  const out = [];
  for (const m of String(fx ?? '').matchAll(/(?:^|[\s;:\[])TOKEN\s+(?:ME|OPP)\s+([^\s;\]]+)/gi)) {
    const id = m[1].toUpperCase();
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

// Svi problemi fx teksta (prazni retci se preskaču): [{ line, problem }].
export function fxProblems(fx) {
  return String(fx ?? '').split('\n').map(l => l.trim()).filter(Boolean)
    .map(line => ({ line, problem: lineProblem(line) })).filter(p => p.problem);
}
