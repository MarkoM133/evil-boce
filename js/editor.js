// Card editor (zamjena za Card Engine), po Markovim mockupima (docs/private/mockups/card-editor/).
// Stranice: Sets (mreža karata seta), Publish, Traits & aliases, Text guide, Frames; otvorena karta je cijeli ekran
// s trakom (breadcrumb, lock, Undo, Close, Save), lijevo paneli (Checks, panel tipa, fx, Balance, Notes & history),
// u sredini karta, desno forma. Izmjene se spremaju kao nacrti (data/editor/drafts.json); igra ih vidi tek nakon Objave.
// Tekst je u editoru s tokenima ([HP], [PWR]…), u bazi riječima (js/card-text.js).
import { loadTemplate, renderCard, fontsReady, loadImage, parseEffect, templateName, coreMode, TINTS, PHASE_COLORS } from './render.js';
import { firstTag, traitNames, norm, GENERAL, HEROES, TRAIT, INVALID } from './tags.js';
import { TERRAINS } from './parse.js';
import { applyDrafts, imageHashOf } from './importer.js';
import { lockPath, lockState, newLock, LOCK_DIR, HEARTBEAT_MS, SETTLE_MS } from './locks.js';
import { createSetsView } from './editor-sets.js';
import { createGuideView, readGuide, avoidWarnings, suggest } from './editor-guide.js';
import { createFramesView } from './editor-frames.js';
import { toTokens, toWords, headAt, withHeadAt, stripTerrain, withTerrain, coreBonus, coreEffect, PHASES } from './card-text.js';
import { deckPool, heroEvolutions, setTraits } from './deck.js';
import * as fs from './fsdir.js';

export const DRAFTS_PATH = 'data/editor/drafts.json';
const NOTES_PATH = 'data/editor/notes.json';
const WISH_PATH = 'data/fx-wishlist.json';
const HISTORY_PATH = 'data/editor/history.json';
// Zadnja Objava iz editora: baza prije nje i objavljeni nacrti, za Undo.
const LAST_PUBLISH_PATH = 'data/editor/last-publish.json';
export const EDIT_TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage', 'Core'];
export const PAGES = ['sets', 'publish', 'traits', 'guide', 'frames', 'wishlist', 'words'];
const PORTRAIT = ['Action', 'Equipment', 'Assist'];
const HEROISH = ['Hero', 'Evolution'];
const COLORS = Object.keys(TINTS);
const STATUSES = ['draft', 'review', 'done'];
const CORE_KINDS = ['Buff', 'Major', 'Debuff'];
const ROMAN = ['I', 'II', 'III'];
const WHO_KEY = 'evil-boce-who';
const STAT_KEYS = [['hp', 'HP'], ['dmg', 'DMG'], ['pwr', 'PWR'], ['rng', 'RNG'], ['kb', 'KB']];
const TOKENS = ['HP', 'DMG', 'PWR', 'RNG', 'KB'];
// Polja koja editor mijenja; nacrt čuva samo ona koja se razlikuju od karte u cards.json.
const FIELDS = ['name', 'type', 'color', 'bonusColors', 'cost', 'bonus', 'stats', 'evo', 'hero', 'abilityNames', 'traits', 'aliases', 'text', 'terrain',
  'fx', 'fxStatus', 'fxRead', 'art', 'artCrop', 'emblem', 'bg', 'template', 'coreImage', 'status'];
const TYPE_BADGE = { Hero: 'hero', Evolution: 'evolution', Action: 'action', Equipment: 'action', Assist: 'action', Stage: 'stage', Core: 'core' };

// Prazan objekt ili popis je isto što i polje kojeg nema (Stage bez bonusa, karta bez tagova).
const empty = v => v == null || v === '' || (typeof v === 'object' && Object.keys(v).length === 0);
const sameVal = (a, b) => (empty(a) && empty(b)) || JSON.stringify(a) === JSON.stringify(b);
const setOf = id => id.split('-')[0];
const isDefaultCrop = c => !c || (c.x === 0.5 && c.y === 0.5 && (c.zoom ?? 1) === 1);
const when = iso => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const today = new Date().toDateString() === d.toDateString();
  return today ? `today ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : `${d.getDate()}.${d.getMonth() + 1}.`;
};

// env: { state, h, toast, guard, render, go(id), openTab(tab), openEffect(id), assertFresh, commitDb, dropOldImages, renderTraits }
export function createEditor(env) {
  const { h } = env;
  const ed = {
    drafts: null, guide: null, notes: null, history: null, locks: {}, locksAt: 0, tpls: {}, ready: false, agency: true, loading: false, error: null,
    id: null, base: null, work: null, art: null, artFor: null, emblem: null, emblemFor: null, dirty: false,
    undo: [], snapAt: 0, view: 'card', artMode: false, lock: null, last: undefined, balOpen: true, pubOff: new Set(),
    canvas: null, frame: 0, from: 'sets', thumbs: new Map(),
    claude: {}, // Claude prijedlozi fx-a po karti: { waiting, at, res } (vidi askClaude)
  };
  const store = () => env.state.store;
  const canWrite = () => store()?.kind === 'folder';
  const who = () => { try { return localStorage.getItem(WHO_KEY) || ''; } catch { return ''; } };
  const setWho = name => { try { localStorage.setItem(WHO_KEY, name); } catch {} };
  const db = () => env.state.db;

  async function load() {
    if (ed.loading) return;
    ed.loading = true;
    try {
      ed.agency = await fontsReady();
      [ed.drafts, ed.guide, ed.notes, ed.history, ed.wishlist] = await Promise.all([readJson(DRAFTS_PATH, { version: 1, cards: {} }), readGuide(store()), readJson(NOTES_PATH, { cards: {} }), readJson(HISTORY_PATH, { cards: {} }), readJson(WISH_PATH, { version: 1, items: [] })]);
      await readLocks();
      await sets.ensure();
      ed.ready = true;
    } catch (e) {
      ed.error = e.message || String(e);
    }
    ed.loading = false;
    env.render();
  }

  // Uvijek s diska (drugi stroj je mogao spremiti u međuvremenu; Syncthing donese datoteku).
  // Datoteke koje nema daju fallback; datoteka koja se ne da pročitati (Syncthing je upravo mijenja) je greška,
  // da se pozivatelj ne bi zapisao prazan popis preko tuđih nacrta.
  async function readJson(path, fallback) {
    let text;
    if (store().kind === 'folder') text = await fs.readText(store().root, path);
    else {
      const r = await fetch(path, { cache: 'no-store' });
      if (r.status === 404) return structuredClone(fallback);
      if (!r.ok) throw new Error(`${path} could not be read (${r.status}).`);
      text = await r.text();
    }
    if (text == null || !text.trim()) return structuredClone(fallback);
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`${path} is being written right now (or is broken). Try again in a moment.`);
    }
  }
  const readDrafts = () => readJson(DRAFTS_PATH, { version: 1, cards: {} });
  const writeJson = (path, data) => fs.writeFile(store().root, path, JSON.stringify(data, null, 2) + '\n');

  // Predlošci se učitavaju kad zatrebaju (data/card-frames/<ime>/).
  function templateFor(card) {
    const name = templateName(card);
    ed.tpls[name] ??= loadTemplate(name, rel => store().dataUrl(rel));
    return ed.tpls[name];
  }

  // Karte iz cards.json s nacrtima, i nove karte iz nacrta (new: true).
  const merged = c => ({ ...c, ...(ed.drafts?.cards?.[c.id] ?? {}) });
  function allCards() {
    const list = db().cards.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted).map(merged);
    for (const [id, d] of Object.entries(ed.drafts?.cards ?? {})) if (d.new && !db().cards.some(c => c.id === id)) list.push({ id, ...d });
    if (ed.work?.new && !list.some(c => c.id === ed.work.id)) list.push(cardOf(ed.work));
    return list.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  }

  // ---------- radna kopija karte ----------

  // Forma drži tekst s tokenima; Stage bez reda "Terrain:", Core s efektom umjesto bonusa.
  function workOf(card) {
    const w = structuredClone(card);
    w.text = toTokens(card.type === 'Stage' ? stripTerrain(card.text) : card.text);
    w.traits ??= [];
    w.artCrop ??= { x: 0.5, y: 0.5, zoom: 1 };
    if (PORTRAIT.includes(card.type)) w.bonus ??= {};
    if (HEROISH.includes(card.type)) w.stats ??= {};
    if (card.type === 'Core') w.effect = coreEffect(card.bonus);
    return w;
  }

  // Karta kakvu vide renderer, nacrt i igra: riječi, red "Terrain:", bonus Corea iz efekta.
  function cardOf(w) {
    const c = { ...w, text: toWords(w.text) };
    if (w.type === 'Stage') c.text = withTerrain(c.text, w.terrain ?? 'None');
    if (w.type === 'Core') { c.bonus = coreBonus(w.effect); c.text = ''; }
    delete c.effect;
    return c;
  }

  function open(id) {
    const draft = ed.drafts?.cards?.[id];
    const base = db().cards.find(c => c.id === id) ?? (draft?.new ? { id } : null);
    if (!base) { ed.id = null; ed.work = null; return; }
    ed.id = id;
    ed.base = base;
    ed.work = workOf({ ...base, ...(draft ?? {}) });
    ed.opened = cardOf(ed.work);
    ed.canvas = null;
    ed.artCv = null;
    ed.dirty = false;
    ed.undo = [];
    ed.artMode = false;
    ed.view = 'card';
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
  }

  const isCardPage = () => {
    const want = env.state.editId;
    return !!want && !PAGES.includes(want);
  };

  // ---------- prikaz ----------

  function render() {
    if (!ed.ready && !ed.error) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the card editor…'));
    }
    if (ed.error) return h('section', { class: 'panel' }, h('p', { class: 'warn' }, ed.error));
    const want = env.state.editId ?? 'sets';
    if (PAGES.includes(want)) {
      if (ed.id) {
        if (!leaveOk()) return renderCardPage();
        ed.id = null;
        ed.work = null;
      }
      syncLock();
      // Lockovi i cards.json s drugog stroja, najviše svakih 30 s.
      if (Date.now() - ed.locksAt > HEARTBEAT_MS) {
        Promise.all([readLocks(), refreshDb()]).then(([a, b]) => { if (a || b) env.render(); }).catch(() => {});
      }
      return h('div', { class: 'ce-page-wrap' }, readOnlyNote(), pageTabs(want), { sets: sets.render, guide: guide.render, traits: renderTraitsPage, words: renderTraitsPage, frames: frames.render, publish: renderPublish, wishlist: renderWishlist }[want]());
    }
    if (want !== ed.id) {
      if (!leaveOk()) return renderCardPage();
      open(want);
    }
    syncLock();
    if (!ed.work) return h('section', { class: 'panel' }, h('p', { class: 'warn' }, `No card ${want}.`), h('button', { class: 'ghost', onclick: () => go('sets') }, 'Back to Sets'));
    return renderCardPage();
  }

  // Nespremljene izmjene pri odlasku s karte (Natrag, druga stranica): pitaj; "ne" vrati adresu na kartu.
  function leaveOk() {
    if (!ed.dirty || !ed.work) return true;
    if (confirm('Discard the unsaved changes to this card?')) { ed.dirty = false; return true; }
    env.state.editId = ed.id;
    env.state.tab = 'editor';
    setTimeout(env.render, 0);
    return false;
  }

  // Odlazak iz Card editora na drugu stranicu appa: pitaj za nespremljeno i otpusti lock.
  function leave() {
    if (!leaveOk()) return false;
    ed.id = null;
    ed.work = null;
    releaseLock();
    return true;
  }
  window.addEventListener('beforeunload', e => { if (ed.dirty && ed.work) e.preventDefault(); });

  function go(id) {
    if (ed.dirty && id !== ed.id && !confirm('Discard the unsaved changes to this card?')) return;
    ed.dirty = false;
    if (id && !PAGES.includes(id) && (!ed.id || PAGES.includes(env.state.editId ?? 'sets'))) ed.from = env.state.editId ?? 'sets';
    env.go(id);
  }

  // ---------- stranica karte ----------

  // Pregled karta po karta (Marko 2026-11-03, iz mockupa): Prev / Next idu redom kojim je karta otvorena (mreža seta s
  // filterima, ili popis nacrta u Publishu), a "Looks good, next" označi kartu kao done, spremi je i otvori iduću.
  function reviewOrder(id) {
    let ids = ed.from === 'publish' ? draftList().map(x => x.id) : sets.order();
    if (!ids.includes(id)) {
      const set = setOf(id);
      ids = allCards().filter(c => setOf(c.id) === set).map(c => c.id).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    }
    return ids;
  }

  function step(dir) {
    const ids = reviewOrder(ed.id);
    const i = ids.indexOf(ed.id);
    const to = ids[i + dir];
    if (to) go(to);
    return !!to;
  }

  async function looksGood() {
    const w = ed.work;
    if (w.type !== 'Core' && (w.status ?? 'draft') !== 'done') { snap(true); w.status = 'done'; changed(); }
    if (ed.dirty) await saveDraft();
    if (!step(1)) { env.toast('That was the last card here.'); go(ed.from); }
  }

  // ← i → listaju karte dok se ne tipka (polja, popisi, tekst).
  if (!globalThis.__ceArrows) {
    globalThis.__ceArrows = true;
    document.addEventListener('keydown', e => {
      if (!ed.id || !ed.work || e.altKey || e.ctrlKey || e.metaKey || (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight')) return;
      const t = e.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      if (ed.artMode) return;
      e.preventDefault();
      step(e.key === 'ArrowRight' ? 1 : -1);
    });
  }

  function renderCardPage() {
    const w = ed.work;
    const setName = sets.nameOf(w.type === 'Core' ? 'Core' : w.type === 'Stage' ? 'Stage' : setOf(w.id));
    const lockChip = ed.lock?.state === 'other'
      ? h('span', { class: 'ce-lockchip other' }, `🔒 ${ed.lock.other?.who ?? 'Someone'} is editing`,
        h('button', { class: 'ghost', type: 'button', onclick: () => env.guard(() => { releaseLock(); return claimLock(ed.id, who(), true); }) }, 'Take over'))
      : ed.lock?.state === 'mine' ? h('span', { class: 'ce-lockchip' }, '🔒 You are editing')
        : canWrite() && !who() ? h('span', { class: 'ce-lockchip muted' }, 'Set "Signed in as" to lock the card') : null;
    const top = h('header', { class: 'ce-top' },
      h('nav', { class: 'ce-crumbs' },
        h('button', { class: 'link', type: 'button', onclick: () => go('sets') }, 'Card editor'), ' / ',
        h('button', { class: 'link', type: 'button', onclick: () => { sets.pick(w.type === 'Core' ? 'Core' : w.type === 'Stage' ? 'Stage' : setOf(w.id)); go('sets'); } }, setName), ' / ',
        h('strong', {}, `${w.id} ${w.name || 'New card'}`),
        h('span', { class: `ce-badge ${TYPE_BADGE[w.type]}${w.type === 'Action' || w.type === 'Equipment' || w.type === 'Assist' ? ` c-bg-${w.color}` : ''}` }, w.type.toUpperCase())),
      h('div', { class: 'ce-top-actions' }, lockChip, reviewNav(w),
        w.type === 'Core' ? null : h('button', { class: 'ghost', type: 'button', disabled: !ed.undo.length, onclick: undo }, 'Undo'),
        h('button', { class: 'ghost', type: 'button', onclick: () => go(ed.from) }, 'Close'),
        h('button', { class: 'primary', type: 'button', disabled: !canWrite() || ed.lock?.state === 'other', onclick: () => env.guard(saveDraft) }, 'Save')));
    return h('div', { class: 'ce-full' }, top, readOnlyNote(),
      h('div', { class: `ce-cols${HEROISH.includes(w.type) ? ' wide' : ''}` }, renderSide(), renderCentre(), renderForm()));
  }

  function reviewNav(w) {
    const ids = reviewOrder(w.id);
    const i = ids.indexOf(w.id);
    if (i < 0) return null;
    return h('span', { class: 'ce-review' },
      h('button', { class: 'ghost', type: 'button', disabled: i <= 0, title: 'Previous card (←)', onclick: () => step(-1) }, '‹'),
      h('span', { class: 'small muted' }, `${i + 1} / ${ids.length}`),
      h('button', { class: 'ghost', type: 'button', disabled: i >= ids.length - 1, title: 'Next card (→)', onclick: () => step(1) }, '›'),
      w.type === 'Core' ? null : h('button', { class: 'ghost ce-good', type: 'button', disabled: !canWrite() || ed.lock?.state === 'other',
        title: 'Mark it done, save it and open the next card', onclick: () => env.guard(looksGood) }, 'Looks good, next'));
  }

  // Podaci preko servera su samo za gledanje: spremanje, upload i Objava trebaju otvoren zajednički folder.
  function readOnlyNote() {
    if (canWrite()) return null;
    return h('div', { class: 'ce-readonly' },
      h('span', {}, h('strong', {}, 'View only.'), ' The cards come through the server, so Save, art upload and Publish are off. Open the shared folder to edit (Chrome or Edge on a computer).'),
      env.openFolder ? h('button', { class: 'primary', type: 'button', onclick: () => env.openFolder() }, 'Open the folder') : null);
  }

  // ---------- lijevi paneli ----------

  function panel(title, ...kids) {
    return h('section', { class: 'ce-panel' }, h('h3', {}, title), ...kids);
  }

  function renderSide() {
    const w = ed.work;
    ed.checkBox = h('ul', { class: 'ce-checks' });
    const parts = [panel('Checks', ed.checkBox)];
    if (w.type === 'Hero') parts.push(heroPanel(w));
    if (PORTRAIT.includes(w.type)) parts.push(sameFramePanel(w));
    if (w.type === 'Stage') parts.push(panel('Terrain', h('p', { class: 'small' }, 'The terrain line is added to the card by the editor, under the text. It is not typed in the text.')));
    if (w.type === 'Core') parts.push(panel('Cores', h('p', { class: 'small' }, 'Cores are not in a set. They have their own list in Card editor › Sets.')));
    if (w.type !== 'Core') parts.push(fxPanel(w));
    if (PORTRAIT.includes(w.type)) { ed.balBox = h('div', {}); parts.push(ed.balBox); } else ed.balBox = null;
    parts.push(notesPanel(w));
    return h('aside', { class: 'ce-side' }, ...parts);
  }

  function heroPanel(w) {
    const evos = db().cards.filter(c => c.type === 'Evolution' && !c.deleted && c.hero === w.name);
    return panel('Hero cards',
      h('p', { class: 'small' }, 'Aliases: ', h('strong', {}, (w.aliases ?? []).join(', ') || '–')),
      h('p', { class: 'small' }, 'Evolutions: ', evos.length ? evos.map((e, i) => [i ? ', ' : null, h('button', { class: 'link', type: 'button', onclick: () => go(e.id) }, e.name.split(/,\s*/).pop())]).flat().filter(Boolean) : 'none yet',
        ' · ', h('button', { class: 'link accent', type: 'button', onclick: () => newCard(setOf(w.id), 'Evolution', { hero: w.name, color: w.color }) }, 'New evolution')));
  }

  // Action, Equipment i Assist dijele okvir; sličice iste karte s drugim tipom (klik promijeni tip).
  function sameFramePanel(w) {
    const others = PORTRAIT.filter(t => t !== w.type);
    const figs = others.map(t => {
      const c = h('canvas', { class: 'ce-mini' });
      thumbInto(c, { ...cardOf(w), type: t }, 96);
      return h('button', { class: 'ce-mini-fig', type: 'button', title: `Make it ${t}`, onclick: () => { snap(true); w.type = t; changed(); env.render(); } }, c, h('span', {}, t));
    });
    return panel('Same frame', h('p', { class: 'small' }, `${PORTRAIT.join(', ').replace(/, (?=[^,]*$)/, ' and ')} share this frame. Only the small type label changes.`), h('div', { class: 'ce-minis' }, figs));
  }

  // Claude prijedlog fx-a (Marko 2026-11-03): zahtjev ide u data/fx-requests/ u zajedničkom folderu, server na
  // Markovom računalu (server/fx-claude.mjs, ključ samo tamo) pita Claude i vrati odgovor u data/fx-claude/.
  const CLAUDE_REQ = id => `data/fx-requests/${id}.json`;
  const CLAUDE_RES = id => `data/fx-claude/${id}.json`;
  const claudeText = w => toWords(w.text ?? '');

  function claudeRequest(c, text, at) {
    const p = env.state.fxProposals?.cards?.[c.id];
    const base = db().cards.find(x => x.id === c.id);
    // Čitanje parsera vrijedi samo za objavljeni tekst; server ga uspoređuje, Claude ga ne vidi.
    const read = p && !p.unparsed?.length && base && toWords(base.text ?? '') === text ? (p.read ?? '') : undefined;
    return { id: c.id, name: c.name, type: c.type, color: c.color, bonusColors: c.bonusColors, hero: c.hero, cost: c.cost,
      traits: c.traits, text, read, who: who(), at };
  }

  async function askClaude(w) {
    const at = new Date().toISOString();
    const req = claudeRequest(w, claudeText(w), at);
    await fs.writeFile(store().root, CLAUDE_REQ(w.id), JSON.stringify(req, null, 2) + '\n');
    ed.claude[w.id] = { waiting: true, at, res: ed.claude[w.id]?.res ?? null };
    env.render();
    pollClaude(w.id, at);
  }

  // Čeka odgovor (Syncthing ga donese za par sekundi dok je Markov server upaljen); najviše ~10 minuta.
  async function pollClaude(id, at, tries = 0) {
    const res = await readJson(CLAUDE_RES(id), null).catch(() => null);
    const st = ed.claude[id];
    if (!st || st.at !== at) return;
    if (res && res.askedAt === at) {
      ed.claude[id] = { waiting: false, at, res };
      if (ed.id === id) env.render();
      return;
    }
    if (tries > 200) { ed.claude[id] = { ...st, waiting: false, late: true }; if (ed.id === id) env.render(); return; }
    setTimeout(() => pollClaude(id, at, tries + 1), 3000);
  }

  async function loadClaude(id) {
    if (ed.claude[id] || !store()) return;
    ed.claude[id] = { waiting: false, at: null, res: null };
    const res = await readJson(CLAUDE_RES(id), null).catch(() => null);
    if (res) { ed.claude[id] = { waiting: false, at: res.askedAt, res }; if (ed.id === id) env.render(); }
  }

  function claudeBlock(w, box) {
    loadClaude(w.id);
    const st = ed.claude[w.id] ?? {};
    const r = st.res;
    const ask = h('button', { class: 'ghost', type: 'button', disabled: !canWrite() || st.waiting || !claudeText(w).trim(),
      title: !canWrite() ? 'Open the shared folder to ask Claude' : 'Claude proposes the fx on Marko\'s computer; it comes back here in a few seconds',
      onclick: () => env.guard(() => askClaude(w)) }, st.waiting ? 'Asking Claude…' : r ? 'Ask Claude again' : 'Ask Claude');
    const parts = [ask];
    if (st.waiting) parts.push(h('p', { class: 'small muted' }, 'Waiting for Claude. Marko\'s computer answers while its Card Studio server runs; the request waits in the folder otherwise.'));
    if (st.late) parts.push(h('p', { class: 'small warn' }, 'No answer yet. Is the server on Marko\'s computer running? The request is still in the folder.'));
    if (r?.error) parts.push(h('p', { class: 'small warn' }, `Claude could not answer: ${r.error}`));
    else if (r) {
      const stale = r.askedText != null && r.askedText !== claudeText(w);
      const use = () => { snap(true); w.fx = r.fx || undefined; w.fxStatus = r.fx ? 'check' : undefined; box.value = r.fx ?? ''; changed(); env.render(); };
      const normFx = x => String(x ?? '').split('\n').map(l => l.trim().replace(/\s+/g, ' ').toUpperCase()).filter(Boolean).join('\n');
      const inUse = !!r.fx && normFx(w.fx) === normFx(r.fx);
      parts.push(h('div', { class: 'ce-claude' },
        h('p', { class: 'small muted' }, `Claude's proposal${r.who ? ` (asked by ${r.who})` : ''}${stale ? ', for an older text' : ''}:`),
        h('pre', { class: 'ce-fx-code ce-claude-fx' }, r.fx || '(no fx needed)'),
        r.problems?.length ? h('p', { class: 'small warn' }, 'The game would not read: ', r.problems.map(p => `${p.line} (${p.problem})`).join(' · ')) : null,
        r.unsure?.length ? h('ul', { class: 'small ce-claude-unsure' }, r.unsure.map(u => h('li', {}, u))) : null,
        r.notes ? h('p', { class: 'small' }, r.notes) : null,
        r.agree === true ? h('p', { class: 'small ok' }, '✓ Claude reads the card the same way as the game.') : r.agree === false ? h('p', { class: 'small warn' }, 'Claude reads it differently from the game: compare the two and fix the text, or use Claude\'s fx.') : null,
        r.extensions?.length ? h('p', { class: 'small' }, 'Needs new words, on the ', h('button', { class: 'link', type: 'button', onclick: () => go('wishlist') }, 'fx wishlist'), ': ', r.extensions.map(x => x.word).join(' · ')) : null,
        // Once the fx box holds this proposal, say so instead of offering it again (Marko 2026-11-05).
        inUse ? h('p', { class: `small ${w.fxStatus === 'check' ? 'warn' : 'ok'}` }, w.fxStatus === 'check' ? '✓ In the fx box. Confirm it below.' : '✓ In the fx box and confirmed.')
          : h('button', { class: 'ghost', type: 'button', disabled: !!r.problems?.length || stale, title: r.problems?.length ? 'The game would not read it' : stale ? 'Ask again: the text changed' : 'Put it in the fx box, still to be confirmed', onclick: use }, 'Use this')));
    }
    return h('div', { class: 'ce-claude-box' }, parts);
  }

  // Kartice na vrhu spojenih stranica: Publish | Waiting for the game, Tags | Phrases (Marko 2026-11-03).
  function pageTabs(want) {
    const groups = [
      [['publish', 'Publish'], ['wishlist', 'Waiting for the game']],
      [['traits', 'Tags'], ['guide', 'Phrases']],
    ];
    const cur = want === 'words' ? 'traits' : want;
    const group = groups.find(g => g.some(([k]) => k === cur));
    if (!group) return null;
    const wishes = (ed.wishlist?.items ?? []).filter(i => i.status === 'open').length;
    const drafts = Object.keys(ed.drafts?.cards ?? {}).length;
    return h('div', { class: 'ce-views ce-page-tabs' }, group.map(([k, label]) => h('button', { type: 'button', class: k === cur ? 'active' : '', onclick: () => go(k) },
      label, k === 'wishlist' && wishes ? h('span', { class: 'tab-badge' }, wishes) : k === 'publish' && drafts ? h('span', { class: 'tab-badge' }, drafts) : null)));
  }

  // fx wishlist (Marko 2026-11-03): riječi koje fx jeziku fale, iz Claude prijedloga (server/fx-claude.mjs).
  // Glagoli, uvjeti i mete čekaju Claude Code da ih ugradi u igru ("napravi wishlist"); "rule" je pitanje za Marka.
  async function setWish(key, status) {
    const fresh = await readJson(WISH_PATH, { version: 1, items: [] });
    const item = fresh.items.find(i => i.key === key);
    if (!item) return;
    item.status = status;
    item.by = who();
    item.changedAt = new Date().toISOString();
    await writeJson(WISH_PATH, fresh);
    ed.wishlist = fresh;
    env.render();
  }

  // Claude pročita svaku kartu sam i server usporedi s parserom igre (Marko 2026-11-03).
  const checkable = () => allCards().filter(c => c.type !== 'Core' && !c.deleted && (c.text ?? '').trim());

  async function loadAllClaude() {
    if (ed.claudeAllAt && Date.now() - ed.claudeAllAt < HEARTBEAT_MS) return;
    ed.claudeAllAt = Date.now();
    await Promise.all(checkable().map(async c => {
      const res = await readJson(CLAUDE_RES(c.id), null).catch(() => null);
      if (res && !ed.claude[c.id]?.waiting) ed.claude[c.id] = { waiting: false, at: res.askedAt, res };
    }));
    env.render();
  }

  async function checkAll() {
    const todo = checkable().filter(c => {
      const r = ed.claude[c.id]?.res;
      return !ed.claude[c.id]?.waiting && (!r || r.error || r.askedText !== toWords(c.text ?? ''));
    });
    if (!todo.length) { env.toast('Every card already has an answer from Claude for its current text.'); return; }
    if (!confirm(`Ask Claude to read ${todo.length} cards (about ${Math.max(1, Math.round(todo.length * 0.03))} USD)? The answers come in while the server on Marko's computer runs.`)) return;
    for (const c of todo) {
      const at = new Date().toISOString();
      await fs.writeFile(store().root, CLAUDE_REQ(c.id), JSON.stringify(claudeRequest(c, toWords(c.text ?? ''), at), null, 2) + '\n');
      ed.claude[c.id] = { waiting: true, at, res: ed.claude[c.id]?.res ?? null };
      pollClaude(c.id, at);
    }
    env.toast(`${todo.length} cards asked.`);
    env.render();
  }

  function claudeCheckSection() {
    loadAllClaude();
    const cards = checkable();
    const st = c => ed.claude[c.id] ?? {};
    const differ = cards.filter(c => st(c).res?.agree === false);
    const agree = cards.filter(c => st(c).res?.agree === true).length;
    const waiting = cards.filter(c => st(c).waiting).length;
    const unchecked = cards.filter(c => !st(c).res && !st(c).waiting).length;
    return h('section', { class: 'ce-claude-check' },
      h('h3', {}, 'Claude reads every card'),
      h('p', { class: 'muted small' }, 'Claude writes the fx of each card from its text on its own, and the server compares it with what the game reads. Where they agree the reading is checked twice; where they differ, one of them misread the text.'),
      h('p', { class: 'small' }, `${agree} agree · ${differ.length} differ · ${waiting} waiting · ${unchecked} not checked`),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), title: 'Cards without fx get the game\'s reading, to confirm while you review them', onclick: () => env.guard(fillAllFx) }, 'Write fx on every card'),
        h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(checkAll) }, 'Check every card with Claude')),
      differ.length ? h('div', { class: 'ce-wish-list' }, differ.map(c => h('article', { class: 'ce-wish' },
        h('div', { class: 'ce-wish-head' }, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, `${c.id} ${c.name}`)),
        h('p', { class: 'small muted' }, toWords(c.text ?? '')),
        h('div', { class: 'ce-fx-pair' },
          h('div', {}, h('p', { class: 'small muted' }, 'The game reads'), h('pre', { class: 'ce-fx-code ce-claude-fx' }, st(c).res.read || '(nothing)')),
          h('div', {}, h('p', { class: 'small muted' }, 'Claude reads'), h('pre', { class: 'ce-fx-code ce-claude-fx' }, st(c).res.fx || '(nothing)')))))) : null);
  }

  function renderWishlist() {
    if (Date.now() - (ed.wishAt ?? 0) > HEARTBEAT_MS) {
      ed.wishAt = Date.now();
      readJson(WISH_PATH, { version: 1, items: [] }).then(x => { if (JSON.stringify(x) !== JSON.stringify(ed.wishlist)) { ed.wishlist = x; env.render(); } }).catch(() => {});
    }
    const items = ed.wishlist?.items ?? [];
    const card = (it, label) => h('article', { class: `ce-wish ${it.status}` },
      h('div', { class: 'ce-wish-head' }, h('code', {}, it.word), h('span', { class: 'ce-chip' }, label), it.status !== 'open' ? h('span', { class: 'muted small' }, it.status === 'done' ? 'in the game' : 'not needed') : null),
      h('p', {}, it.meaning),
      h('p', { class: 'small muted' }, it.why),
      h('ul', { class: 'small ce-wish-cards' }, it.cards.map(c => h('li', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, `${c.id} ${c.name ?? ''}`), c.fx ? [' ', h('code', {}, c.fx)] : null))),
      it.status === 'open' ? h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => setWish(it.key, 'dismissed')) }, 'Not needed')
        : it.status === 'dismissed' ? h('button', { class: 'link small', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => setWish(it.key, 'open')) }, 'Back on the list') : null);
    const open = items.filter(i => i.status === 'open');
    const words = open.filter(i => i.kind !== 'rule');
    const rules = open.filter(i => i.kind === 'rule');
    const closed = items.filter(i => i.status !== 'open');
    return h('section', { class: 'ce-wishlist' },
      claudeCheckSection(),
      h('p', { class: 'muted' }, 'Words the fx language does not have yet, proposed by Claude while it wrote fx (Ask Claude on a card). New verbs, conditions and targets wait for Claude Code to build them into the game: tell it "napravi wishlist". Rules are questions for Marko.'),
      h('h3', {}, `For the game (${words.length})`),
      words.length ? h('div', { class: 'ce-wish-list' }, words.map(i => card(i, i.kind))) : h('p', { class: 'muted small' }, 'Nothing waiting.'),
      h('h3', {}, `Rule questions for Marko (${rules.length})`),
      rules.length ? h('div', { class: 'ce-wish-list' }, rules.map(i => card(i, 'rule'))) : h('p', { class: 'muted small' }, 'None.'),
      closed.length ? h('details', {}, h('summary', {}, `Done or not needed (${closed.length})`), h('div', { class: 'ce-wish-list' }, closed.map(i => card(i, i.kind)))) : null);
  }

  // fx za igru (Marko 2026-11-05): svaka karta ima zapisan fx i igra radi po njemu. Parser igre (data/fx-proposals.json,
  // nakon Objave) i Claude samo predlažu; čovjek potvrdi. Promjena teksta fx vrati na nepotvrđen.
  function gameProposal(w, p, textChanged) {
    if (textChanged || !p || p.unparsed?.length || !(w.text ?? '').trim()) return null;
    const read = p.read ?? '';
    const norm = x => String(x ?? '').split('\n').map(l => l.trim().replace(/\s+/g, ' ').toUpperCase()).filter(Boolean).join('\n');
    if (w.fx && norm(w.fx) === norm(read)) return null;
    return h('div', { class: 'ce-claude' },
      h('p', { class: 'small muted' }, w.fx ? 'The game would read the text as:' : 'The game reads the text as (proposal):'),
      h('pre', { class: 'ce-fx-code ce-claude-fx' }, read || '(nothing to run)'),
      h('button', { class: 'ghost', type: 'button', disabled: !canWrite() || !read, title: 'Put it in the fx box, still to be confirmed', onclick: () => { snap(true); w.fx = read; w.fxStatus = 'check'; changed(); env.render(); } }, 'Use this'));
  }

  function fxPanel(w) {
    const p = env.state.fxProposals?.cards?.[w.id];
    const textChanged = !w.new && toWords(w.text ?? '') !== (ed.base.type === 'Stage' ? stripTerrain(ed.base.text) : ed.base.text ?? '');
    const box = h('textarea', { class: 'ce-fx-code', rows: 4, spellcheck: false, placeholder: 'No fx yet: use a proposal below, or write it.', value: w.fx ?? '',
      oninput: e => { snap(); w.fx = e.target.value.trim() ? e.target.value : undefined; w.fxStatus = w.fx ? 'ok' : undefined; changed(); } });
    const note = !w.fx ? (textChanged || w.new ? 'No fx yet. The game\'s proposal comes after Publish; Ask Claude works now.' : !p ? 'No fx yet, and no report from the game for this card.' : p.unparsed?.length ? `No fx yet. The game does not understand: ${p.unparsed.join(' · ')}` : 'No fx yet.')
      : w.fxStatus === 'check' ? 'Not confirmed: a proposal, or the text changed after it. Check it against the text, then Confirm (or edit it) and Save.'
        : '✓ Confirmed: the game plays this fx.';
    return h('section', { class: 'ce-panel' },
      h('div', { class: 'ce-panel-head' }, h('h3', {}, 'fx for the game')),
      box, h('p', { class: `small ${!w.fx || w.fxStatus === 'check' ? 'warn' : 'ok'}` }, note),
      w.fx && w.fxStatus === 'check' ? h('button', { class: 'ghost', type: 'button', onclick: () => { snap(true); w.fxStatus = 'ok'; changed(); env.render(); } }, 'Confirm fx') : null,
      gameProposal(w, p, textChanged),
      claudeBlock(w, box),
      !w.new && env.openEffect ? h('button', { class: 'link small', type: 'button', onclick: () => env.openEffect(w.id) }, 'What the game reads →') : null);
  }

  // Jednom za sve: kartama bez fx-a upiše prijedlog igre (nepotvrđen); potvrđuje se tijekom pregleda.
  // Karta s potvrđenim čitanjem (fxRead, prijašnji način) dobije fx potvrđen.
  async function fillAllFx() {
    const fresh = await readDrafts();
    fresh.cards ??= {};
    const props = env.state.fxProposals?.cards ?? {};
    let n = 0;
    let confirmed = 0;
    for (const base of db().cards) {
      if (base.deleted || base.type === 'Core' || !(base.text ?? '').trim()) continue;
      const d = fresh.cards[base.id] ?? {};
      if ('text' in d && toWords(d.text ?? '') !== (base.text ?? '')) continue;
      if (d.fx ?? base.fx) continue;
      const p = props[base.id];
      if (!p || p.unparsed?.length || !p.read) continue;
      if (ed.locks[base.id] && lockState(ed.locks[base.id], who()) === 'other') continue;
      const was = d.fxRead ?? base.fxRead;
      const ok = was != null && was === p.read;
      const nd = { ...d, fx: p.read, fxStatus: ok ? 'ok' : 'check', updated: new Date().toISOString(), who: who() || undefined };
      delete nd.fxRead;
      fresh.cards[base.id] = nd;
      n++;
      if (ok) confirmed++;
    }
    if (!n) { env.toast('Every card with a game reading already has an fx.'); return; }
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    env.toast(`fx written on ${n} ${n === 1 ? 'card' : 'cards'} (${n - confirmed} to confirm). They go into the game with the next Publish.`);
    env.render();
  }

  function notesPanel(w) {
    const notes = [...(ed.notes?.cards?.[w.id] ?? [])];
    if (typeof ed.base.notes === 'string' && ed.base.notes) notes.unshift({ who: '', at: '', text: ed.base.notes });
    const hist = [...(ed.history?.cards?.[w.id] ?? [])].reverse();
    // Objave prije povijesti editora: iz changelog.json (bez imena).
    const published = (env.state.changelog?.entries ?? []).filter(e => e.cards?.some(c => c.id === w.id)).map(e => ({ at: e.date, what: `published v${e.version}` })).reverse();
    const lines = [...hist, ...published.filter(p => !hist.some(x => x.what === p.what))].slice(0, 8);
    const input = h('input', { placeholder: 'Add a note…', onkeydown: e => { if (e.key === 'Enter') { e.preventDefault(); env.guard(() => addNote(e.target.value)); } } });
    return panel('Notes & history',
      ...notes.map(n => h('div', { class: 'ce-note' }, h('p', { class: 'small' }, h('strong', { class: n.who === 'Marko' ? 'red' : '' }, n.who || 'Note'), n.at ? ` · ${when(n.at)}` : ''), h('p', {}, n.text))),
      canWrite() ? input : null,
      ...lines.map(x => h('p', { class: 'small' }, h('strong', {}, x.who || ''), `${x.who ? ' · ' : ''}${when(x.at)} · ${x.what}`)),
      lines.length || notes.length ? null : h('p', { class: 'small muted' }, 'Nothing yet.'),
      ed.drafts?.cards?.[w.id] ? h('button', { class: 'link small', type: 'button', disabled: !canWrite(), onclick: () => env.guard(discardDraft) }, w.new ? 'Throw away this new card' : 'Discard the unpublished changes') : null);
  }

  async function addNote(text) {
    if (!text.trim()) return;
    const fresh = await readJson(NOTES_PATH, { cards: {} });
    (fresh.cards[ed.id] ??= []).push({ who: who() || '', at: new Date().toISOString(), text: text.trim() });
    await writeJson(NOTES_PATH, fresh);
    ed.notes = fresh;
    env.render();
  }

  async function logHistory(id, what) {
    const fresh = await readJson(HISTORY_PATH, { cards: {} });
    (fresh.cards[id] ??= []).push({ who: who() || '', at: new Date().toISOString(), what });
    if (fresh.cards[id].length > 50) fresh.cards[id] = fresh.cards[id].slice(-50);
    await writeJson(HISTORY_PATH, fresh);
    ed.history = fresh;
  }

  // ---------- sredina: karta ----------

  function renderCentre() {
    const w = ed.work;
    const views = w.type === 'Core' ? [] : HEROISH.includes(w.type) ? [['card', 'Card'], ['board', 'On the board'], ['old', 'Old vs new']]
      : w.type === 'Stage' ? [['card', 'Card'], ['map', 'On the map'], ['old', 'Old vs new']] : [['card', 'Card'], ['old', 'Old vs new']];
    if (!views.some(([k]) => k === ed.view)) ed.view = 'card';
    const wide = HEROISH.includes(w.type);
    // Isto platno između crtanja: novo prazno platno bi na trenutak bljesnulo.
    const [cw, chh] = wide ? [2100, 1500] : [1500, 2100];
    if (!ed.canvas || ed.canvas.width !== cw || ed.canvas.height !== chh) ed.canvas = h('canvas', { width: cw, height: chh });
    ed.stage = h('div', { class: `ce-stage${wide ? ' wide' : ''}${ed.artMode ? ' art-mode' : ''}${w.type === 'Core' ? ' core' : ''}` });
    ed.warn = [];
    queueDraw();
    const fileIn = h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', hidden: true, onchange: e => env.guard(() => uploadArt(e.target.files[0])) });
    const buttons = w.type === 'Core' ? [] : ed.artMode ? [] : [
      h('button', { class: 'ghost', type: 'button', disabled: !ed.artFor && !w.art, onclick: () => { ed.artMode = true; env.render(); } }, 'Edit art'),
      h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => fileIn.click() }, w.art ? 'Replace art' : 'Add art'),
      w.type === 'Stage' ? null : h('button', { class: 'ghost', type: 'button', onclick: () => { if (!leaveOk()) return; ed.work = null; ed.id = null; env.toast('Remove background works on a plain background colour: save the PNG there, then Replace art.'); env.openTab('tools'); } }, 'Remove background'),
      h('button', { class: 'ghost', type: 'button', title: 'A new card with the next code in this set', onclick: duplicate }, 'Duplicate'),
      h('button', { class: 'ghost', type: 'button', onclick: downloadPng }, 'Download PNG'),
    ];
    return h('section', { class: 'ce-centre' },
      views.length > 1 && !ed.artMode ? h('div', { class: 'ce-views' }, views.map(([k, label]) => h('button', { type: 'button', class: ed.view === k ? 'active' : '', onclick: e => {
        ed.view = k;
        for (const b of e.currentTarget.parentNode.children) b.classList.toggle('active', b === e.currentTarget);
        paintStage(cardOf(ed.work));
      } }, label))) : null,
      ed.stage,
      ed.artMode ? h('div', { class: 'ce-zoom' }, h('span', {}, 'ZOOM'),
        h('input', { type: 'range', min: 0.5, max: 3, step: 0.01, value: w.artCrop.zoom, oninput: e => { snap(); w.artCrop = { ...w.artCrop, zoom: Number(e.target.value) }; changed(); } }),
        h('button', { class: 'primary', type: 'button', onclick: () => { ed.artMode = false; env.render(); } }, 'Done')) : null,
      ed.artMode ? h('p', { class: 'muted small ce-hint' }, HEROISH.includes(w.type) ? 'Drag the art to move it, scroll to zoom. The frame covers the right edge of the art.' : 'Drag the art to move it, scroll to zoom. The dashed line is the art window.') : null,
      w.type === 'Core' ? h('p', { class: 'muted small ce-hint' }, 'Image only, no frame') : null,
      buttons.length ? h('div', { class: 'ce-art-buttons' }, buttons, fileIn) : null,
      ed.agency ? null : h('p', { class: 'warn small' }, 'Agency FB is not on this computer: a stand-in font is shown. PNGs are made on a computer that has it.'));
  }

  // Više izmjena u istom trenutku daje jedno crtanje.
  function queueDraw() {
    if (ed.frame) return;
    ed.frame = 1;
    setTimeout(async () => {
      ed.frame = 0;
      await draw().catch(e => console.error(e));
    }, 0);
  }

  async function draw() {
    const w = ed.work;
    if (!w || !ed.canvas) return;
    const card = cardOf(w);
    const tpl = await templateFor(card);
    // Forma heroja čita zadanu boju pozadine iz predloška: kad predložak stigne prvi put, nacrta se iznova.
    const first = ed.tpl?.name !== tpl.name;
    ed.tpl = tpl;
    if (first && HEROISH.includes(w.type) && !w.bg) { env.render(); return; }
    if (ed.artFor !== w.art) {
      const want = w.art;
      ed.artFor = want;
      const url = want ? await store().dataUrl(want) : null;
      const img = url ? await loadImage(url).catch(() => null) : null;
      if (ed.artFor === want) ed.art = img;
    }
    const emblemPath = w.emblem ?? (w.type === 'Evolution' ? heroCard(w)?.emblem ?? ed.drafts?.cards?.[heroCard(w)?.id]?.emblem : null);
    if (ed.emblemFor !== emblemPath) {
      ed.emblemFor = emblemPath;
      const url = emblemPath ? await store().dataUrl(emblemPath) : null;
      ed.emblem = url ? await loadImage(url).catch(() => null) : null;
    }
    if (w !== ed.work) return;
    ed.warn = renderCard(ed.canvas, card, tpl, ed.art, ed.emblem);
    paintStage(card);
    if (ed.checkBox) ed.checkBox.replaceChildren(...checks(w, card).map(([ok, text]) => h('li', { class: ok ? 'ok' : 'bad' }, h('span', { class: 'mark' }, ok ? '✓' : '!'), text)));
    if (ed.balBox) ed.balBox.replaceChildren(...renderBalance(card));
  }

  const heroCard = w => {
    const name = w.hero;
    const c = db().cards.find(x => x.type === 'Hero' && !x.deleted && x.name === name);
    return c ? merged(c) : null;
  };

  // Pogled u sredini: karta, u ruci, uvećana, stara i nova, ili način uređivanja arta (slika i izvan karte).
  function paintStage(card) {
    const st = ed.stage;
    if (!st) return;
    if (ed.artMode) {
      const c = artCanvas();
      if (c.parentNode !== st) st.replaceChildren(c);
      return;
    }
    const view = ed.view;
    if (view === 'card') { st.replaceChildren(ed.canvas); ed.canvas.className = 'ce-canvas'; return; }
    const scaled = px => {
      const c = h('canvas', { width: px * 2, height: Math.round((px * 2 * ed.canvas.height) / ed.canvas.width) });
      c.style.width = `${px}px`;
      const g = c.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(ed.canvas, 0, 0, c.width, c.height);
      return c;
    };
    const wide = ed.canvas.width > ed.canvas.height;
    if (view === 'hand') st.replaceChildren(h('figure', { class: 'ce-ctx' }, scaled(wide ? 168 : 120), h('figcaption', { class: 'muted small' }, 'Size in the hand')));
    else if (view === 'board') boardView(card).then(c => { if (ed.view === 'board' && ed.stage === st) st.replaceChildren(c); });
    else if (view === 'map') st.replaceChildren(mapView(card));
    else if (view === 'hover') st.replaceChildren(h('figure', { class: 'ce-ctx' }, scaled(wide ? 392 : 280), h('figcaption', { class: 'muted small' }, 'Size when you hover it in the game')));
    else {
      const old = h('img', { class: 'ce-old', alt: 'Published' });
      if (ed.base.image) store().imageUrl(ed.base).then(u => { if (u) old.src = u; });
      st.replaceChildren(h('div', { class: 'ce-oldnew' },
        h('figure', {}, ed.base.image ? old : h('div', { class: 'ce-old empty' }, 'Not published yet'), h('figcaption', { class: 'muted small' }, 'Published')),
        h('figure', {}, scaled(wide ? 360 : 260), h('figcaption', { class: 'muted small' }, 'New'))));
    }
  }

  // Ploča kao u igri: tamni heksi (šiljasti vrh), R polumjer, (cx, cy) središte; vraća središta.
  function hexBoard(g, W, H, R) {
    const dx = Math.sqrt(3) * R;
    const dy = 1.5 * R;
    const centres = [];
    g.fillStyle = '#231e1a';
    g.fillRect(0, 0, W, H);
    for (let row = -1; row * dy < H + R; row++) {
      for (let col = -1; col * dx < W + dx; col++) {
        const x = col * dx + (row % 2 ? dx / 2 : 0);
        const y = row * dy;
        hexPath(g, x, y, R - 1.5);
        g.fillStyle = '#3a312a';
        g.fill();
        centres.push([x, y]);
      }
    }
    return { dx, dy, centres };
  }

  function hexPath(g, x, y, r) {
    g.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = Math.PI / 6 + (i * Math.PI) / 3;
      g[i ? 'lineTo' : 'moveTo'](x + r * Math.cos(a), y + r * Math.sin(a));
    }
    g.closePath();
  }

  // On the board: figurica heroja (sprite iz igre) na heksu s prstenom tima, i ploča heroja kao u igri.
  async function boardView(card) {
    const W = 960;
    const H = 600;
    const c = h('canvas', { class: 'ce-canvas', width: W, height: H });
    const g = c.getContext('2d');
    const R = 46;
    const { dx, dy } = hexBoard(g, W, H, R);
    const row = Math.round(380 / dy);
    const col = Math.round((W / 2 - (row % 2 ? dx / 2 : 0)) / dx);
    const x = col * dx + (row % 2 ? dx / 2 : 0);
    const y = row * dy;
    hexPath(g, x, y, R - 1.5);
    g.fillStyle = '#4a4036';
    g.fill();
    g.strokeStyle = '#2f6bff';
    g.lineWidth = 6;
    g.beginPath();
    g.ellipse(x, y, R * 0.62, R * 0.3, 0, 0, Math.PI * 2);
    g.stroke();
    const base = db().cards.find(b => b.id === card.id);
    const spritePath = card.sprite ?? base?.sprite ?? (card.type === 'Evolution' ? db().cards.find(b => b.type === 'Hero' && b.name === card.hero)?.sprite : null);
    const url = spritePath ? await store().dataUrl(spritePath) : null;
    const sprite = url ? await loadImage(url).catch(() => null) : null;
    if (sprite) {
      const sh = 230;
      const sw = (sprite.width / sprite.height) * sh;
      g.imageSmoothingEnabled = false;
      g.drawImage(sprite, x - sw / 2, y - sh + R * 0.2, sw, sh);
      g.imageSmoothingEnabled = true;
    } else {
      g.fillStyle = '#8d8a85';
      g.font = '600 20px "Barlow Semi Condensed", sans-serif';
      g.textAlign = 'center';
      g.fillText('No standee sprite yet', x, y - R * 1.4);
    }
    // Ploča heroja (lijevo gore), kao u igri: lice s arta, ime, HP kao crtice, statsi.
    const px = 24;
    const py = 24;
    g.fillStyle = 'rgba(12, 12, 12, 0.92)';
    g.fillRect(px, py, 420, 112);
    g.fillStyle = TINTS[card.color] ?? '#f4b62a';
    g.fillRect(px + 416, py, 4, 112);
    // Lice: kvadrat s vrha prozora arta na nacrtanoj karti.
    const win = ed.tpl?.layout?.artWindow;
    if (ed.art && win) g.drawImage(ed.canvas, win[0], win[1], win[2], win[2], px, py, 112, 112);
    g.fillStyle = '#f3efe7';
    g.textAlign = 'left';
    g.font = 'italic 800 30px "Barlow Condensed", sans-serif';
    const title = card.type === 'Evolution' ? (card.name ?? '').split(/,\s*/).pop() : card.name ?? '';
    g.fillText(title, px + 126, py + 38);
    const hp = card.stats?.hp ?? 0;
    for (let i = 0; i < hp; i++) {
      g.fillStyle = '#23b14d';
      g.fillRect(px + 126 + i * (270 / Math.max(hp, 1)), py + 52, 270 / Math.max(hp, 1) - 4, 9);
    }
    g.font = '700 17px "Barlow Condensed", sans-serif';
    const st = card.stats ?? {};
    const parts = [['PWR', st.pwr, '#f4b62a'], ['DMG', st.dmg, '#ff5a4f'], ['RNG', st.rng, '#22c7dd'], ['KB', st.kb, '#7fa2ff']];
    let tx = px + 126;
    for (const [label, v, col] of parts) {
      g.fillStyle = col;
      g.fillText(`${label} ${v ?? '–'}`, tx, py + 92);
      tx += g.measureText(`${label} ${v ?? '–'}`).width + 16;
    }
    return c;
  }

  // On the map: Stage kao cvijet od 7 heksa na ploči, art unutra, žuti obrub i oznaka terena kao u igri.
  function mapView(card) {
    const W = 960;
    const H = 600;
    const c = h('canvas', { class: 'ce-canvas', width: W, height: H });
    const g = c.getContext('2d');
    const R = 58;
    const { dx, dy } = hexBoard(g, W, H, R);
    const row = Math.round(300 / dy);
    const col = Math.round((W / 2 - (row % 2 ? dx / 2 : 0)) / dx);
    const cx = col * dx + (row % 2 ? dx / 2 : 0);
    const cy = row * dy;
    const flower = [[0, 0], [dx, 0], [-dx, 0], [dx / 2, dy], [-dx / 2, dy], [dx / 2, -dy], [-dx / 2, -dy]].map(([ox, oy]) => [cx + ox, cy + oy]);
    g.strokeStyle = '#f4c22f';
    g.lineWidth = 8;
    for (const [x, y] of flower) { hexPath(g, x, y, R); g.stroke(); }
    g.save();
    g.beginPath();
    for (const [x, y] of flower) {
      for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + (i * Math.PI) / 3;
        g[i ? 'lineTo' : 'moveTo'](x + R * Math.cos(a), y + R * Math.sin(a));
      }
      g.closePath();
    }
    g.clip();
    const fw = dx * 3;
    const fh = R * 2 + dy * 2;
    if (ed.art) {
      const k = Math.max(fw / ed.art.width, fh / ed.art.height);
      g.drawImage(ed.art, cx - (ed.art.width * k) / 2, cy - (ed.art.height * k) / 2, ed.art.width * k, ed.art.height * k);
    } else {
      g.fillStyle = '#1b1b1f';
      g.fillRect(cx - fw / 2, cy - fh / 2, fw, fh);
    }
    g.fillStyle = 'rgba(0, 0, 0, 0.18)';
    g.fillRect(cx - fw / 2, cy - fh / 2, fw, fh);
    g.restore();
    const tc = { Ice: '#bfe9ff', Mud: '#c89a6a', Ramp: '#f4c22f', Wind: '#c8fff4' }[card.terrain];
    g.textAlign = 'center';
    if (tc) {
      g.font = 'italic 800 34px "Barlow Condensed", sans-serif';
      g.lineWidth = 6;
      g.strokeStyle = 'rgba(0, 0, 0, 0.75)';
      g.strokeText(card.terrain.toUpperCase(), cx, cy + dy + 12);
      g.fillStyle = tc;
      g.fillText(card.terrain.toUpperCase(), cx, cy + dy + 12);
    }
    g.font = 'italic 800 30px "Barlow Condensed", sans-serif';
    g.fillStyle = '#f3efe7';
    g.fillText(card.name ?? '', cx, cy - dy - R - 18);
    return c;
  }

  // Edit art: cijela slika (zatamnjena izvan karte), karta preko nje, isprekidani prozor arta; povlačenje i kotačić.
  function artCanvas() {
    const L = ed.tpl.layout;
    const W = ed.canvas.width;
    const H = ed.canvas.height;
    const M = Math.round(W * 0.07);
    // Jedno platno dok traje Edit art: povlačenje drži pointer na njemu, crta se samo iznova.
    let c = ed.artCv;
    if (!c || c.width !== W + M * 2 || c.height !== H + M * 2) {
      c = ed.artCv = h('canvas', { class: 'ce-canvas ce-artcanvas', width: W + M * 2, height: H + M * 2 });
      hookDrag(c);
    }
    const g = c.getContext('2d');
    g.setLineDash([]);
    g.fillStyle = '#141418';
    g.fillRect(0, 0, c.width, c.height);
    const art = ed.art;
    if (art) {
      const [bx, by, bw, bh] = L.artBox;
      const cr = { x: 0.5, y: 0.5, zoom: 1, ...ed.work.artCrop };
      const s = Math.max(bw / art.width, bh / art.height) * Math.max(cr.zoom, 0.05);
      const dw = art.width * s;
      const dh = art.height * s;
      g.globalAlpha = 0.45;
      g.drawImage(art, M + bx + bw / 2 - cr.x * dw, M + by + bh / 2 - cr.y * dh, dw, dh);
      g.globalAlpha = 1;
    }
    g.drawImage(ed.canvas, M, M);
    const win = L.artWindow ?? L.artBox;
    g.setLineDash([22, 14]);
    g.lineWidth = 5;
    g.strokeStyle = '#f4c22f';
    g.strokeRect(M + win[0], M + win[1], win[2], win[3]);
    return c;
  }

  // Povlačenje arta pomiče izrez, kotačić zumira (samo u načinu Edit art).
  function hookDrag(canvas) {
    let from = null;
    canvas.addEventListener('pointerdown', e => { from = { x: e.clientX, y: e.clientY, crop: { ...ed.work.artCrop } }; snap(true); canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener('pointermove', e => {
      if (!from || !ed.art) return;
      const scale = canvas.width / canvas.getBoundingClientRect().width;
      const [, , bw, bh] = ed.tpl.layout.artBox;
      const k = Math.max(bw / ed.art.width, bh / ed.art.height) * from.crop.zoom;
      ed.work.artCrop = { ...from.crop, x: from.crop.x - ((e.clientX - from.x) * scale) / (ed.art.width * k), y: from.crop.y - ((e.clientY - from.y) * scale) / (ed.art.height * k) };
      changed();
    });
    canvas.addEventListener('pointerup', () => { from = null; });
    canvas.addEventListener('wheel', e => {
      e.preventDefault();
      snap();
      const z = Math.min(3, Math.max(0.5, ed.work.artCrop.zoom * (e.deltaY < 0 ? 1.05 : 1 / 1.05)));
      ed.work.artCrop = { ...ed.work.artCrop, zoom: z };
      const slider = document.querySelector('.ce-zoom input');
      if (slider) slider.value = z;
      changed();
    }, { passive: false });
  }

  // Sličica karte (Sets, Same frame, Publish): nacrta se jednom po verziji karte i čuva.
  const thumbQueue = [];
  let thumbBusy = false;
  function thumbInto(canvas, card, px) {
    const key = JSON.stringify([card.id, card.type, card.updated ?? card.rev, card.art, card.artCrop, card.text, card.name, card.color, card.cost, card.traits, card.bonus, card.stats, card.emblem, card.coreImage]);
    const wide = HEROISH.includes(card.type);
    canvas.width = px * 2;
    canvas.height = Math.round(px * 2 * (wide ? 1500 / 2100 : 2100 / 1500));
    canvas.style.width = `${px}px`;
    const paint = src => canvas.getContext('2d').drawImage(src, 0, 0, canvas.width, canvas.height);
    const done = ed.thumbs.get(key);
    if (done) { paint(done); return; }
    thumbQueue.push({ canvas, card, key, paint });
    pumpThumbs();
  }
  async function pumpThumbs() {
    if (thumbBusy) return;
    thumbBusy = true;
    while (thumbQueue.length) {
      const { card, key, paint } = thumbQueue.shift();
      try {
        if (!ed.thumbs.has(key)) {
          const tpl = await templateFor(card);
          const url = card.art ? await store().dataUrl(card.art) : null;
          const art = url ? await loadImage(url).catch(() => null) : null;
          const eu = card.emblem ? await store().dataUrl(card.emblem) : null;
          const emblem = eu ? await loadImage(eu).catch(() => null) : null;
          const full = document.createElement('canvas');
          renderCard(full, card, tpl, art, emblem);
          const small = document.createElement('canvas');
          small.width = 360;
          small.height = Math.round((360 * full.height) / full.width);
          const g = small.getContext('2d');
          g.imageSmoothingQuality = 'high';
          g.drawImage(full, 0, 0, small.width, small.height);
          ed.thumbs.set(key, small);
        }
        paint(ed.thumbs.get(key));
      } catch (e) {
        console.error(e);
      }
      await new Promise(r => setTimeout(r, 0));
    }
    thumbBusy = false;
  }

  // ---------- desna forma ----------

  function renderForm() {
    const w = ed.work;
    const traits = traitNames(env.state.traits?.traits);
    const set = (k, v) => { snap(true); w[k] = v; changed(); };
    const field = (label, input, extra) => h('label', { class: 'ce-field' }, h('span', {}, label), input, extra ?? null);
    const num = (value, oninput, opts = {}) => h('input', { type: 'number', value: value ?? '', placeholder: '–', oninput, ...opts });
    const code = field('CODE', h('input', { value: w.id, disabled: true }));
    const seg = (items, value, onpick) => h('div', { class: 'ce-seg' }, items.map(([v, label]) => h('button', { type: 'button', class: v === value ? 'active' : '', onclick: () => onpick(v) }, label)));
    const text = textEditor(w);
    const statusRow = w.type === 'Core' ? null : h('div', { class: 'ce-status' }, h('span', { class: 'small muted' }, 'STATUS'),
      seg(STATUSES.map(s => [s, s]), w.status ?? 'draft', v => { set('status', v); env.render(); }));
    let body;
    if (w.type === 'Hero' || w.type === 'Evolution') {
      const evo = w.type === 'Evolution';
      const heroes = db().cards.filter(c => c.type === 'Hero' && !c.deleted);
      const bgVal = w.bg || ed.tpl?.layout?.bg?.[w.color] || '';
      const hc = evo ? heroCard(w) : null;
      const emblemFile = h('input', { type: 'file', accept: 'image/png,image/webp', hidden: true, onchange: e => env.guard(() => uploadEmblem(e.target.files[0])) });
      const unlock = evo && hc ? w.traits.filter(t => !(hc.traits ?? []).some(x => norm(x) === norm(t))) : [];
      body = [
        h('h2', {}, w.type),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        evo ? h('div', { class: 'ce-row' },
          field('BASE HERO', h('select', { onchange: e => { const x = heroes.find(c => c.name === e.target.value); snap(true); w.hero = e.target.value; if (x) w.color = x.color; changed(); env.render(); } },
            h('option', { value: '' }, '–'), heroes.map(x => h('option', { value: x.name, selected: x.name === w.hero }, `${x.name} (${x.id})`)))),
          field('LEVEL', h('select', { onchange: e => set('evo', Number(e.target.value)) }, ROMAN.map((r, i) => h('option', { value: i + 1, selected: i + 1 === (w.evo ?? 1) }, r))))) : null,
        h('div', { class: 'ce-row' },
          evo ? field('COST', num(w.cost ?? 0, e => set('cost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 }))
            : field('COLOR', h('select', { onchange: e => { set('color', e.target.value); env.render(); } }, COLORS.map(c => h('option', { value: c, selected: c === w.color }, c)))),
          field('BACKGROUND', h('div', { class: 'ce-bg' },
            h('input', { type: 'color', value: /^#[0-9a-f]{6}$/i.test(bgVal) ? bgVal : '#000000', oninput: e => { set('bg', e.target.value); const t = e.target.nextSibling; if (t) t.value = e.target.value; } }),
            h('input', { value: bgVal, placeholder: 'colour default', oninput: e => { if (/^#[0-9a-f]{6}$/i.test(e.target.value)) set('bg', e.target.value); else if (!e.target.value) { snap(true); delete w.bg; changed(); } } }))),
          code),
        h('div', { class: 'ce-emblem' },
          h('span', { class: 'ce-emblem-dot' }, ed.emblem ? h('img', { src: ed.emblem.src, alt: '' }) : 'LOGO'),
          h('div', {}, h('span', { class: 'small muted' }, 'EMBLEM'),
            h('p', { class: 'small' }, w.emblem ? w.emblem.split('/').pop() : evo ? 'Taken from base hero' : 'None yet', ' · ',
              h('button', { class: 'link accent', type: 'button', disabled: !canWrite(), onclick: () => emblemFile.click() }, w.emblem || evo ? 'replace' : 'add'),
              w.emblem && evo ? [' · ', h('button', { class: 'link', type: 'button', onclick: () => { snap(true); delete w.emblem; ed.emblemFor = undefined; changed(); env.render(); } }, 'use base hero')] : null)),
          emblemFile),
        h('h2', {}, 'Stats'),
        h('div', { class: 'ce-row ce-stats' }, STAT_KEYS.map(([k, label]) => field(h('span', { class: `stat-${k}` }, label), num(w.stats[k], e => set('stats', { ...w.stats, [k]: e.target.value === '' ? undefined : Number(e.target.value) }), { step: k === 'pwr' ? 1000 : 1 })))),
        w.type === 'Hero' ? field('ALIASES', h('input', { value: (w.aliases ?? []).join(', '), placeholder: 'Trish', oninput: e => set('aliases', e.target.value.split(',').map(x => x.trim()).filter(Boolean)) }), h('small', { class: 'muted' }, 'Other names a card\'s first tag may use for this hero.')) : null,
        h('h2', {}, 'Ability'),
        field('ABILITY NAME', h('input', { value: w.abilityNames?.[0] ?? '', oninput: e => set('abilityNames', [e.target.value, ...(w.abilityNames ?? []).slice(1)]) })),
        ...text,
        h('h2', {}, 'Traits'),
        chips(w, 0, traits, unlock),
        unlock.length ? h('p', { class: 'small muted' }, 'Cards with first tag ', h('strong', { class: 'accent' }, unlock.join(', ')), ' need this evolution in the deck.') : null,
      ];
    } else if (PORTRAIT.includes(w.type)) {
      // Colorless karta: prvi tag smije biti bilo koji heroj.
      const heroes = db().cards.filter(c => c.type === 'Hero' && !c.deleted && (w.color === 'None' || c.color === w.color));
      const firstOptions = [['General', 'General'], ...heroes.map(x => [x.name, `${x.name} (hero)`]), ...traits.map(t => [t, `${t} (trait)`])];
      if (w.traits[0] && !firstOptions.some(([v]) => v === w.traits[0])) firstOptions.push([w.traits[0], `${w.traits[0]} (unknown)`]);
      body = [
        h('h2', {}, 'Card'),
        field('TYPE', seg(PORTRAIT.map(t => [t, t]), w.type, v => { set('type', v); env.render(); })),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, field('COST', num(w.cost ?? 0, e => set('cost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 })), code),
        field('COLOR', h('div', { class: 'ce-swatches' },
          COLORS.map(c => h('button', { type: 'button', class: `ce-swatch${c === w.color ? ' active' : ''}`, style: `--sw: var(--c-${c})`, title: c, 'aria-label': c, onclick: () => { snap(true); w.color = c; delete w.bonusColors; changed(); env.render(); } })),
          h('button', { type: 'button', class: `ce-swatch colorless${w.color === 'None' ? ' active' : ''}`, style: '--sw: var(--c-colorless)', title: 'Colorless: any hero may play it', 'aria-label': 'Colorless',
            onclick: () => { snap(true); if (w.color !== 'None' && COLORS.includes(w.color)) w.bonusColors = [w.color]; w.color = 'None'; changed(); env.render(); } }, 'C'))),
        w.color === 'None' ? field('BONUS COLOURS (UP TO 2)', h('div', { class: 'ce-bonuscols' }, COLORS.map(c => {
          const on = (w.bonusColors ?? []).includes(c);
          return h('button', { type: 'button', class: `ce-bonuscol${on ? ' on' : ''}`, style: `--sw: var(--c-${c})`, 'aria-pressed': String(on), onclick: () => {
            snap(true);
            const cur = w.bonusColors ?? [];
            w.bonusColors = on ? cur.filter(x => x !== c) : [...cur, c];
            if (!w.bonusColors.length) delete w.bonusColors;
            changed();
            env.render();
          } }, h('span', { class: 'dot' }), c);
        })), h('small', { class: 'muted' }, 'The bonus applies when the hero it is played for is one of these colours. Write it in the text as "Red Bonus: …".')) : null,
        field('BONUS', h('div', { class: 'ce-row ce-stats' }, STAT_KEYS.map(([k, label]) => field(h('span', { class: `stat-${k}` }, label), num(w.bonus[k], e => {
          const b = { ...w.bonus };
          if (e.target.value === '' || Number(e.target.value) === 0) delete b[k]; else b[k] = Number(e.target.value);
          set('bonus', b);
        }, { step: k === 'pwr' ? 1000 : 1 }))))),
        h('h2', {}, 'Effect text'),
        ...text,
        h('h2', {}, 'Tags'),
        field('FIRST TAG (WHO MAY PLAY THE CARD)', h('select', { onchange: e => set('traits', [e.target.value, ...w.traits.slice(1)]) },
          h('option', { value: '' }, '–'), firstOptions.map(([v, label]) => h('option', { value: v, selected: v === w.traits[0] }, label)))),
        chips(w, 1, traits, []),
      ];
    } else if (w.type === 'Stage') {
      body = [
        h('h2', {}, 'Stage'),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, field('TERRAIN', h('select', { onchange: e => set('terrain', e.target.value) }, TERRAINS.map(t => h('option', { value: t, selected: t === (w.terrain ?? 'None') }, t)))), code),
        h('p', { class: 'small muted' }, 'No cost, color or tags on Stage cards.'),
        h('h2', {}, 'Effect text'),
        ...text,
      ];
    } else {
      const mode = coreMode(cardOf(w));
      const fileIn = h('input', { type: 'file', accept: 'image/png,image/webp', hidden: true, onchange: e => env.guard(() => uploadArt(e.target.files[0])) });
      const effect = h('input', { class: 'mono', value: w.effect ?? '', oninput: e => { snap(); w.effect = e.target.value; changed(); } });
      const tok = t => { snap(true); const a = effect.selectionStart ?? effect.value.length; effect.value = `${effect.value.slice(0, a)}[${t}]${effect.value.slice(a)}`; w.effect = effect.value; changed(); };
      body = [
        h('h2', {}, 'Core'),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        code,
        field('KIND', seg(CORE_KINDS.map(k => [k, k]), w.traits[0], v => { set('traits', [v]); env.render(); })),
        h('h2', {}, 'Effect'),
        h('div', { class: 'ce-tools' }, TOKENS.map(t => h('button', { type: 'button', class: `tok tok-${t.toLowerCase()}`, onclick: () => tok(t) }, `[${t}]`))),
        field('TEXT', effect),
        h('h2', {}, 'Image'),
        seg([['effect', 'Made from the effect'], ['upload', 'Upload image']], mode, v => { if (v === 'upload' && !w.art) { fileIn.click(); return; } set('coreImage', v); env.render(); }),
        h('p', { class: 'small muted' }, 'The editor draws the hexagon with the effect text and icon. Upload replaces it with your own picture.'),
        fileIn,
      ];
    }
    return h('section', { class: `ce-form c-tint-${w.color ?? 'none'}` }, ...body, statusRow,
      canWrite() ? null : h('p', { class: 'small muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer).'));
  }

  // Tagovi kao čipovi (× makne), polje "Add trait…" s prijedlozima iz popisa traitova. from: 1 = bez prvog taga.
  function chips(w, from, traits, accent) {
    const addTag = () => {
      const t = add.value.trim();
      if (!t) return;
      snap(true);
      if (!w.traits.includes(t)) w.traits = [...(from && !w.traits.length ? [''] : []), ...w.traits, t];
      changed();
      env.render();
    };
    const add = h('input', { list: 'ce-traits', placeholder: from ? 'Add tag…' : 'Add trait…', onkeydown: e => { if (e.key === 'Enter') { e.preventDefault(); addTag(); } } });
    return h('div', { class: 'ce-chips' },
      w.traits.slice(from).map((t, i) => h('span', { class: `ce-chip${accent.includes(t) ? ' accent' : ''}` }, t,
        h('button', { type: 'button', 'aria-label': `Remove ${t}`, onclick: () => { snap(true); w.traits = w.traits.filter((_, j) => j !== i + from); changed(); env.render(); } }, '×'))),
      add, h('button', { class: 'ghost ce-chip-add', type: 'button', onclick: addTag }, '+ Add'),
      h('datalist', { id: 'ce-traits' }, traits.map(t => h('option', { value: t }))));
  }

  // Tekst s prekidačima faze, Once per turn i Range, tokenima statova i prijedlozima iz vodiča.
  function textEditor(w) {
    const stage = w.type === 'Stage';
    const area = h('textarea', { rows: 4, value: w.text ?? '' });
    // Prijedlozi dok pišeš: padajući izbornik ispod teksta (↑ ↓, Enter ili Tab uzme, Esc zatvori).
    // "[" nudi ikone statova; dva ili više slova nude fraze iz vodiča koje tako počinju.
    const pop = h('ul', { class: 'ce-ac', role: 'listbox', hidden: true });
    let caret = area.value.length;
    let sug = { from: 0, items: [] };
    let pick = 0;
    const sync = () => {
      snap();
      w.text = area.value;
      if (w.fx && w.fxStatus !== 'check') w.fxStatus = 'check';
      changed();
      refreshToggles();
    };
    const close = () => { pop.hidden = true; sug = { from: 0, items: [] }; };
    const take = item => {
      const at = area.selectionStart ?? area.value.length;
      const before = area.value.slice(0, sug.from);
      const after = area.value.slice(at);
      // Razmak ispred fraze (ne iza broja ili zagrade) i iza nje, ako ga nema.
      const lead = item.token || !before || /[\s([]$/.test(before) ? '' : ' ';
      const trail = item.token || /[\s:]$/.test(item.insert) || /^[\s.,;:!?]/.test(after) ? '' : ' ';
      const text = lead + item.insert + trail;
      area.value = before + text + after;
      area.selectionStart = area.selectionEnd = before.length + text.length;
      area.focus();
      close();
      sync();
    };
    const paint = () => {
      pop.replaceChildren(...sug.items.map((it, i) => h('li', { role: 'option', 'aria-selected': String(i === pick), class: i === pick ? 'on' : '',
        onmousedown: e => { e.preventDefault(); take(it); } },
      h('span', { class: it.token ? `tok tok-${it.token.toLowerCase()}` : '' }, it.label), it.note ? h('small', { class: 'muted' }, it.note) : null)));
      pop.hidden = !sug.items.length;
    };
    const showSuggest = () => {
      const caret = area.selectionStart ?? area.value.length;
      const before = area.value.slice(0, caret);
      if (before.endsWith('[')) {
        sug = { from: caret - 1, items: TOKENS.map(t => ({ label: `[${t}]`, insert: `[${t}]`, token: t, note: { HP: 'heal / health', DMG: 'damage', PWR: 'Power', RNG: 'Range', KB: 'Knockback' }[t] })) };
      } else {
        const g = suggest(ed.guide, area.value, caret);
        const notes = new Map((ed.guide?.phrases ?? []).map(p => [p.text, p.label]));
        sug = { from: g.from, items: g.items.map(it => ({ label: toTokens(it.insert).trim(), insert: toTokens(it.insert).replace(/\s+$/, ''), note: notes.get(it.insert) })) };
      }
      pick = 0;
      paint();
    };
    area.addEventListener('input', () => { caret = area.selectionStart ?? caret; sync(); showSuggest(); });
    area.addEventListener('blur', () => setTimeout(close, 120));
    area.addEventListener('keydown', e => {
      if (pop.hidden || !sug.items.length) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        pick = (pick + (e.key === 'ArrowDown' ? 1 : -1) + sug.items.length) % sug.items.length;
        paint();
      } else if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault();
        take(sug.items[pick]);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        close();
      }
    });
    const insert = s => {
      snap(true);
      const a = area.selectionStart ?? area.value.length;
      const b = area.selectionEnd ?? a;
      area.value = area.value.slice(0, a) + s + area.value.slice(b);
      area.selectionStart = area.selectionEnd = a + s.length;
      area.focus();
      sync();
    };
    // Prekidači rade na efektu u kojem je kursor (karta može imati više efekata, svaki u svom retku).
    const here = () => headAt(area.value, caret);
    const setHead = patch => {
      snap(true);
      const r = withHeadAt(area.value, caret, patch);
      area.value = r.text;
      caret = r.caret;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    };
    const phaseBtns = PHASES.filter(p => !stage || ['Start', 'Battle', 'End'].includes(p)).map(p => h('button', { type: 'button', 'data-phase': p, style: `--tint: ${PHASE_COLORS[p.toUpperCase()]}`, onmousedown: e => e.preventDefault(), onclick: () => setHead({ phase: here().phase === p ? null : p }) }, p));
    // Passive: the effect has no phase (cards that stay in play draw a PASSIVE chip for it; Marko 2026-11-05).
    const passiveType = ['Hero', 'Evolution', 'Equipment', 'Assist'].includes(w.type);
    const passiveBtn = passiveType ? h('button', { type: 'button', 'data-passive': '1', style: `--tint: ${PHASE_COLORS.PASSIVE}`, title: 'No phase: the effect counts all the time', onmousedown: e => e.preventDefault(), onclick: () => setHead({ phase: null, once: false }) }, 'Passive') : null;
    const once = stage ? null : h('button', { type: 'button', 'data-once': '1', onmousedown: e => e.preventDefault(), onclick: () => { const hd = here(); setHead({ once: !hd.once, phase: hd.phase ?? 'Battle' }); } }, 'Once per turn');
    const range = stage ? null : h('button', { type: 'button', 'data-range': '1', onmousedown: e => e.preventDefault(), onclick: () => setHead({ range: !here().range }) }, '◎ Range');
    // Novi efekt: novi redak na kraju, kursor u njemu (pa se bira njegova faza).
    const addEffect = stage ? null : h('button', { type: 'button', class: 'ce-add-effect', onmousedown: e => e.preventDefault(), onclick: () => {
      snap(true);
      area.value = area.value.replace(/\s+$/, '') + (area.value.trim() ? '\n' : '');
      caret = area.value.length;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    } }, '+ Effect');
    for (const ev of ['click', 'keyup', 'select']) area.addEventListener(ev, () => { caret = area.selectionStart ?? caret; refreshToggles(); });
    const revealed = stage ? h('button', { type: 'button', onclick: () => { if (!/^When this Stage is revealed/i.test(area.value)) { area.value = `When this Stage is revealed, ${area.value}`; area.selectionStart = area.selectionEnd = area.value.length; sync(); } } }, 'When revealed') : null;
    const toks = TOKENS.map(t => h('button', { type: 'button', class: `tok tok-${t.toLowerCase()}`, onclick: () => insert(`[${t}]`) }, `[${t}]`));
    const trait = PORTRAIT.includes(w.type) ? h('button', { type: 'button', class: 'tok', title: 'A trait in the text, e.g. {Sword}', onclick: () => insert('{}') }, '{Trait}') : null;
    const phrase = ed.guide?.phrases?.length ? h('select', { class: 'ce-phrase', 'aria-label': 'Insert a phrase', onchange: e => { const p = ed.guide.phrases[Number(e.target.value)]; e.target.value = ''; if (p) insert(toTokens(p.text)); } },
      h('option', { value: '' }, 'Phrase from the guide…'), ed.guide.phrases.map((p, i) => h('option', { value: i, title: p.note ?? '' }, `${p.label}: ${p.text.trim()}`))) : null;
    // Colorless: red s bonusom za odabrane boje ("Cyan / Purple Bonus: ").
    const bonusBtn = w.color === 'None' ? h('button', { type: 'button', class: 'ce-add-effect', onmousedown: e => e.preventDefault(), onclick: () => {
      const cols = (w.bonusColors ?? []).length ? w.bonusColors : ['Red'];
      snap(true);
      area.value = area.value.replace(/\s+$/, '') + (area.value.trim() ? '\n' : '') + `${cols.join(' / ')} Bonus: `;
      caret = area.value.length;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    } }, '+ Bonus') : null;
    const tools = h('div', { class: 'ce-tools' }, revealed, passiveBtn, phaseBtns, once, range, addEffect, bonusBtn, toks, trait, phrase);
    function refreshToggles() {
      const hd = here();
      for (const b of tools.querySelectorAll('[data-phase]')) b.classList.toggle('on', b.dataset.phase === hd.phase);
      tools.querySelector('[data-passive]')?.classList.toggle('on', !hd.phase && !!hd.rest?.trim());
      tools.querySelector('[data-once]')?.classList.toggle('on', hd.once);
      tools.querySelector('[data-range]')?.classList.toggle('on', hd.range);
    }
    refreshToggles();
    return [tools, h('label', { class: 'ce-field' }, h('span', {}, 'TEXT'), h('div', { class: 'ce-ac-wrap' }, area, pop)),
      h('p', { class: 'muted small ce-ac-hint' }, stage ? 'Type [ for a stat icon, or the start of a phrase from the Text guide: a list opens under the text.'
        : 'Each effect is its own line; the phase buttons set the effect the cursor is in (+ Effect starts a new one). Type [ for a stat icon or the start of a phrase for suggestions.')];
  }

  // ---------- izmjene, Undo ----------

  // Snimka prije izmjene; tipkanje u nizu (do 1,5 s) je jedna snimka. force: svaka radnja svoja.
  function snap(force = false) {
    const now = Date.now();
    if (!force && now - ed.snapAt < 1500) { ed.snapAt = now; return; }
    ed.snapAt = now;
    ed.undo.push(JSON.stringify(ed.work));
    if (ed.undo.length > 100) ed.undo.shift();
    const btn = document.querySelector('.ce-top-actions button[disabled]');
    if (btn?.textContent === 'Undo') btn.disabled = false;
  }

  function undo() {
    const prev = ed.undo.pop();
    if (!prev) return;
    ed.work = JSON.parse(prev);
    ed.snapAt = 0;
    ed.dirty = true;
    env.render();
  }

  function changed() {
    ed.dirty = true;
    queueDraw();
  }

  // ---------- provjere ----------

  // [ok, tekst]: kvačice za ono što je u redu, ! za ono što treba pogledati.
  function checks(w, card) {
    const out = [];
    const traitList = env.state.traits?.traits;
    const fxp = env.state.fxProposals?.cards?.[w.id];
    const textChanged = !w.new && toWords(w.text ?? '') !== (ed.base.type === 'Stage' ? stripTerrain(ed.base.text) : ed.base.text ?? '');
    const gameReads = () => {
      if (!(card.text ?? '').trim()) return;
      if (w.fx) out.push([w.fxStatus !== 'check', w.fxStatus === 'check' ? 'The fx is not confirmed yet' : 'fx confirmed for the game']);
      else out.push([false, 'No fx yet']);
    };
    if (!(w.name ?? '').trim()) out.push([false, 'No name yet']);
    if (PORTRAIT.includes(w.type)) {
      const k = firstTag(db(), card, traitList);
      if (k.kind === HEROES) out.push([true, `First tag "${k.tag}" is a hero${k.heroes.length > 1 ? 'es' : ''}${k.heroes.some(n => n !== k.tag) ? ' alias' : ''}`]);
      else if (k.kind === TRAIT) out.push([true, `First tag "${k.tag}" is a trait`]);
      else if (k.kind === GENERAL) out.push([true, 'First tag General: any hero of this colour']);
      else out.push([false, k.tag ? `First tag "${k.tag}" is not a hero, alias or trait` : 'No first tag: who may play it?']);
      const avoid = avoidWarnings(ed.guide, card.text);
      out.push(avoid.length ? [false, avoid[0]] : [true, 'Phrases match the text guide']);
      gameReads();
    }
    if (w.color === 'None' && PORTRAIT.includes(w.type)) {
      const cols = w.bonusColors ?? [];
      const lines = [...(w.text ?? '').matchAll(/^(Cyan|Yellow|Purple|Red|Blue|Green)((?:\s*\/\s*(?:Cyan|Yellow|Purple|Red|Blue|Green))*)\s+Bonus\s*:/gim)]
        .flatMap(m => m[0].replace(/\s+Bonus\s*:$/i, '').split('/').map(x => x.trim().toLowerCase()));
      if (!cols.length) out.push([false, 'Colorless without bonus colours']);
      else if (cols.length > 2) out.push([false, 'More than 2 bonus colours: only as an exception, with the same bonus']);
      else out.push([true, `Colorless, bonus for ${cols.join(' / ')}`]);
      const missing = cols.filter(c => !lines.includes(c.toLowerCase()));
      const extra = lines.filter(l => !cols.some(c => c.toLowerCase() === l));
      if (missing.length) out.push([false, `No "${missing.join(' / ')} Bonus:" line in the text`]);
      if (extra.length) out.push([false, `The text has a bonus for ${extra.join(', ')}, which is not a bonus colour`]);
    }
    if (HEROISH.includes(w.type)) {
      if (w.type === 'Evolution') {
        const hc = heroCard(w);
        out.push(hc ? [true, `Base hero ${hc.name} is in the set`] : [false, 'Pick the base hero']);
      }
      const names = traitNames(traitList).map(norm);
      for (const t of w.traits.filter(t => names.includes(norm(t))).slice(0, 2)) out.push([true, `Trait "${t}" known`]);
      if (!w.abilityNames?.[0]) out.push([false, 'No ability name']);
      if (!w.emblem && !(w.type === 'Evolution' && heroCard(w)?.emblem)) out.push([false, 'No emblem on the plate']);
    }
    if (w.type === 'Stage') out.push([!!w.terrain && w.terrain !== '', `Terrain set (${w.terrain ?? 'None'})`]);
    if (w.type === 'Core') {
      out.push(Object.keys(card.bonus ?? {}).length ? [true, 'The game reads the effect'] : [false, 'Write the bonus, e.g. +2000[PWR]']);
      if (!CORE_KINDS.includes(w.traits[0])) out.push([false, 'Pick Buff, Major or Debuff']);
    }
    if (w.type !== 'Core') {
      const atMin = ed.warn.some(x => /smallest size/.test(x));
      if ((card.text ?? '').trim()) out.push(atMin ? [false, 'The text only fits at the smallest size'] : [true, 'Text fits']);
      if (!w.art) out.push([false, 'No art yet']);
    }
    for (const x of ed.warn.filter(x => !/smallest size|No art yet/.test(x))) out.push([false, x.replace(/\.$/, '')]);
    if (w.type === 'Stage' || HEROISH.includes(w.type)) gameReads();
    if (w.type === 'Hero') {
      const n = deckPool(liveDb(card), [w.id], heroEvolutions(liveDb(card), [w.id])).filter(c => c.color === w.color).length;
      out.push([n >= 8, `${w.name || 'This hero'} has ${n} cards to play`]);
    }
    if (/\[(?!HP\]|DMG\]|PWR\]|RNG\]|KB\])[^\]]*\]/i.test(w.text ?? '')) out.push([false, 'Only [HP] [DMG] [PWR] [RNG] [KB] go in brackets']);
    return out;
  }

  const liveDb = card => setTraits({ ...db(), cards: [...db().cards.filter(c => c.id !== card.id).map(merged), card] }, db().traitList ?? env.state.traits?.traits);

  // Balans dok uređuješ: krivulja costa boje, slične karte (ista boja i cost), heroji koji je smiju uzeti
  // i koliko karata svoje boje tada imaju (prije → poslije izmjene).
  function renderBalance(card) {
    if (!card.color) return [];
    const pool = [...db().cards.filter(c => !c.deleted && c.id !== card.id).map(merged), card].filter(c => PORTRAIT.includes(c.type) && c.color === card.color);
    const costs = new Map();
    for (const c of pool) costs.set(c.cost ?? 0, (costs.get(c.cost ?? 0) ?? 0) + 1);
    const max = Math.max(1, ...costs.values());
    const top = Math.max(6, ...costs.keys());
    const curve = h('div', { class: 'ce-curve' }, Array.from({ length: top + 1 }, (_, k) => h('div', { class: `ce-bar${k === (card.cost ?? 0) ? ' mine' : ''}`, title: `Cost ${k}: ${costs.get(k) ?? 0}` },
      h('span', { style: `height:${((costs.get(k) ?? 0) / max) * 100}%` }), h('small', {}, String(k)))));
    const similar = pool.filter(c => c.id !== card.id && (c.cost ?? 0) === (card.cost ?? 0));
    const live = liveDb(card);
    const pub = setTraits({ ...db(), cards: db().cards.map(merged) }, db().traitList ?? env.state.traits?.traits);
    const heroes = db().cards.filter(c => c.type === 'Hero' && !c.deleted && (card.color === 'None' || c.color === card.color));
    const own = (d, hero) => deckPool(d, [hero.id], heroEvolutions(d, [hero.id])).filter(c => c.color === hero.color);
    const rows = heroes.map(hero => {
      const before = own(pub, hero).length;
      const after = own(live, hero);
      return { hero, before, after: after.length, takes: after.some(c => c.id === card.id) };
    });
    return [h('details', { class: 'ce-panel', open: ed.balOpen, ontoggle: e => { ed.balOpen = e.target.open; } },
      h('summary', {}, h('h3', {}, 'Balance')),
      h('p', { class: 'small muted' }, `Cost curve of ${card.color} cards:`), curve,
      h('p', { class: 'small' }, similar.length ? `Same colour and cost (${similar.length}):` : 'No other card of this colour has this cost.'),
      similar.length ? h('ul', { class: 'small ce-similar' }, similar.slice(0, 6).map(c => h('li', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, c.name), ` · ${c.type}`))) : null,
      h('p', { class: 'small' }, 'Heroes of this colour (cards they may take):'),
      h('ul', { class: 'small' }, rows.map(r => h('li', { class: r.takes ? '' : 'muted' }, `${r.takes ? '✓' : '–'} ${r.hero.name}: ${r.before}${r.after !== r.before ? ` → ${r.after}` : ''}`))))];
  }

  // ---------- spremanje ----------

  // Nacrt: polja koja se razlikuju od cards.json, tko i kad. Drugi nacrti se čitaju iznova prije pisanja.
  async function saveDraft() {
    if (ed.lock?.state === 'other') throw new Error(`${ed.lock.other?.who ?? 'Someone'} is editing this card.`);
    if (await refreshDb()) {
      rebase();
      env.render();
      throw new Error('The cards were published in the meantime. Fields you did not touch now show the new version; check your changes and Save again.');
    }
    const w = ed.work;
    const card = cardOf(w);
    const diff = {};
    for (const k of FIELDS) {
      if (card[k] === undefined && ed.base[k] === undefined) continue;
      // Izrez na sredini bez zuma je isto što i izrez kojeg nema.
      if (k === 'artCrop' && ed.base[k] == null && isDefaultCrop(card[k])) continue;
      if (!sameVal(card[k], ed.base[k])) diff[k] = card[k] ?? null;
    }
    const fresh = await readDrafts();
    const before = ed.drafts?.cards?.[w.id]?.updated;
    const now = fresh.cards?.[w.id]?.updated;
    if (now && now !== before && !confirm(`${fresh.cards[w.id].who || 'Someone'} saved this card in the meantime. Overwrite?`)) return;
    fresh.cards ??= {};
    if (w.new) diff.new = true;
    const fields = Object.keys(diff).filter(k => k !== 'new');
    if (fields.length || w.new) fresh.cards[w.id] = { ...diff, updated: new Date().toISOString(), who: who() || undefined };
    else delete fresh.cards[w.id];
    await writeJson(DRAFTS_PATH, fresh);
    const prevFields = Object.keys(ed.drafts?.cards?.[w.id] ?? {});
    ed.drafts = fresh;
    ed.dirty = false;
    const what = w.new && !prevFields.length ? 'new card' : fields.filter(k => !prevFields.includes(k) || true).map(k => ({ artCrop: 'art crop', abilityNames: 'ability', traits: 'tags' }[k] ?? k)).join(', ') || 'no changes';
    await logHistory(w.id, `${what.replace(/\btext\b/, 'text changed')}`).catch(() => {});
    env.toast(fields.length || w.new ? `Saved: ${w.name || w.id}. It goes into the game with the next Publish.` : 'No changes against the published card.');
    env.render();
  }

  // cards.json s diska: ako se promijenio (Objava na drugom stroju), app ga preuzme. true kad je nov.
  async function refreshDb() {
    return env.reloadDb ? env.reloadDb() : false;
  }

  // Otvorena karta nakon Objave u međuvremenu: polja koja korisnik nije dirao dobiju novu objavljenu vrijednost.
  function rebase() {
    if (!ed.work || !ed.opened) return;
    const nb = db().cards.find(c => c.id === ed.id);
    if (!nb) return;
    const now = cardOf(ed.work);
    const draft = ed.drafts?.cards?.[ed.id] ?? {};
    const fresh = workOf({ ...nb, ...draft });
    const freshCard = cardOf(fresh);
    for (const k of FIELDS) if (sameVal(now[k], ed.opened[k]) && !(k in draft)) now[k] = freshCard[k];
    ed.base = nb;
    ed.work = workOf(now);
    ed.opened = cardOf(workOf({ ...nb, ...draft }));
  }

  async function discardDraft() {
    if (ed.lock?.state === 'other') throw new Error(`${ed.lock.other?.who ?? 'Someone'} is editing this card.`);
    if (!confirm(ed.work?.new ? 'Throw away this new card?' : 'Throw away the unpublished changes to this card?')) return;
    const fresh = await readDrafts();
    delete fresh.cards?.[ed.id];
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    if (ed.work?.new) { ed.dirty = false; const back = ed.from; ed.work = null; ed.id = null; env.go(back); return; }
    await logHistory(ed.id, 'unpublished changes discarded').catch(() => {});
    open(ed.id);
    env.render();
  }

  // Izvorni art ide u data/art/<kod>.<ext> u punoj rezoluciji; izrez se vraća na sredinu.
  async function uploadArt(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('Art must be PNG, JPEG or WebP.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const path = `art/${ed.work.id}.${await imageHashOf(bytes)}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, bytes);
    store().dropImageUrls?.();
    snap(true);
    ed.work.art = path;
    ed.work.artCrop = { x: 0.5, y: 0.5, zoom: 1 };
    if (ed.work.type === 'Core') ed.work.coreImage = 'upload';
    ed.artFor = null;
    changed();
    env.render();
  }

  // Amblem u pločici heroja: data/art/emblems/<kod>.<ext>.
  async function uploadEmblem(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('The emblem must be PNG or WebP (with a clear background).');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const path = `art/emblems/${ed.work.id}.${await imageHashOf(bytes)}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, bytes);
    store().dropImageUrls?.();
    snap(true);
    ed.work.emblem = path;
    ed.emblemFor = undefined;
    changed();
    env.render();
  }

  function downloadPng() {
    if (!ed.canvas) return;
    ed.canvas.toBlob(b => {
      const a = h('a', { href: URL.createObjectURL(b), download: `${ed.work.id} ${ed.work.name}.png` });
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    }, 'image/png');
  }

  // ---------- nova karta, duplikat ----------

  function nextId(set) {
    const ids = [...db().cards.map(c => c.id), ...Object.keys(ed.drafts?.cards ?? {})];
    const nums = ids.filter(id => id.startsWith(`${set}-`)).map(id => Number(id.slice(set.length + 1))).filter(Number.isFinite);
    return `${set}-${String(Math.max(0, ...nums) + 1).padStart(3, '0')}`;
  }

  const NEW_DEFAULTS = {
    Action: { color: 'Cyan', cost: 1, bonus: {}, traits: ['General'], text: '' },
    Hero: { color: 'Cyan', stats: { hp: 8, dmg: 3, pwr: 2000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Evolution: { color: 'Cyan', cost: 4, evo: 1, hero: '', stats: { hp: 8, dmg: 4, pwr: 3000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Stage: { color: null, traits: [], text: '', terrain: 'None' },
    Core: { color: null, traits: ['Buff'], bonus: { pwr: 1000 }, text: '', coreImage: 'effect' },
  };

  function startCard(id, card) {
    ed.id = id;
    ed.base = { id };
    ed.work = workOf({ ...card, id, new: true, status: 'draft' });
    ed.canvas = null;
    ed.artCv = null;
    ed.dirty = true;
    ed.undo = [];
    ed.artMode = false;
    ed.view = 'card';
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
    if (!PAGES.includes(env.state.editId ?? 'sets')) ed.from = ed.from ?? 'sets';
    else ed.from = env.state.editId ?? 'sets';
    env.go(id);
  }

  function newCard(set, type, extra = {}) {
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    startCard(nextId(set), { name: '', type, ...structuredClone(NEW_DEFAULTS[type] ?? NEW_DEFAULTS.Action), ...extra });
  }

  // Duplikat: ista karta pod sljedećim kodom u istom setu, kao nova karta (nacrt do Objave).
  function duplicate() {
    const w = ed.work;
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    const copy = cardOf(w);
    for (const k of ['image', 'imageHash', 'imageRot', 'imageRotHash', 'sprite', 'spriteHash', 'rev', 'deleted', 'fx', 'fxStatus', 'fxRead', 'aliases', 'updated', 'who', 'new']) delete copy[k];
    startCard(nextId(setOf(w.id)), { ...copy, name: `${w.name ?? ''} (copy)` });
  }

  // ---------- zaključavanje ----------

  // Otvorena karta je zaključana na "Signed in as" dok je otvorena; tuđi lock gasi spremanje.
  async function readLock(id) {
    try { return JSON.parse((await fs.readText(store().root, lockPath(id))) ?? 'null'); } catch { return null; }
  }

  // Svi lockovi (za Sets i Publish); u server načinu ih nema.
  async function readLocks() {
    ed.locksAt = Date.now();
    if (!canWrite()) return false;
    const next = {};
    for (const f of await fs.listFileNames(store().root, LOCK_DIR).catch(() => [])) {
      if (!f.endsWith('.json')) continue;
      const id = f.slice(0, -5);
      const l = await readLock(id);
      if (lockState(l, who()) === 'other') next[id] = l;
    }
    const changed = JSON.stringify(next) !== JSON.stringify(ed.locks);
    ed.locks = next;
    return changed;
  }

  function syncLock() {
    const want = ed.id && canWrite() && who() ? { id: ed.id, who: who() } : null;
    if (ed.lock?.id === want?.id && ed.lock?.who === want?.who) return;
    releaseLock();
    if (want) claimLock(want.id, want.who);
  }

  async function claimLock(id, me, force = false) {
    ed.lock = { id, who: me, state: 'checking' };
    const old = await readLock(id);
    const st = lockState(old, me);
    if (st === 'other' && !force) {
      if (ed.lock?.id === id) { ed.lock = { id, who: me, state: 'other', other: old }; watchLock(id, me); env.render(); }
      return;
    }
    const since = st === 'mine' ? old.since : null;
    if (ed.lock?.id !== id) return;
    await fs.writeFile(store().root, lockPath(id), JSON.stringify(newLock(me, new Date(), since)) + '\n');
    if (ed.lock?.id !== id) {
      // Karta je u međuvremenu zatvorena: lock ne smije ostati.
      fs.removeFile(store().root, lockPath(id)).catch(() => {});
      return;
    }
    ed.lock = { id, who: me, state: 'mine', since: since ?? new Date().toISOString() };
    ed.lock.beat = setInterval(async () => {
      if (ed.lock?.id !== id || ed.lock.state !== 'mine') return;
      const now = await readLock(id);
      // Netko je preuzeo kartu (Take over): odstupi, spremanje se gasi.
      if (now?.who && now.who !== me && lockState(now, me) === 'other') {
        clearInterval(ed.lock.beat);
        ed.lock = { id, who: me, state: 'other', other: now };
        watchLock(id, me);
        env.render();
        return;
      }
      fs.writeFile(store().root, lockPath(id), JSON.stringify(newLock(me, new Date(), ed.lock.since)) + '\n').catch(() => {});
    }, HEARTBEAT_MS);
    // Drugi stroj je možda zaključao u isto vrijeme: Syncthing to donese za par sekundi.
    if (!force) setTimeout(async () => {
      if (ed.lock?.id !== id || ed.lock.state !== 'mine') return;
      const now = await readLock(id);
      if (now?.who && now.who !== me && lockState(now, me) === 'other') {
        clearInterval(ed.lock.beat);
        ed.lock = { id, who: me, state: 'other', other: now };
        watchLock(id, me);
        env.render();
      }
    }, SETTLE_MS);
    env.render();
  }

  // Tuđi lock: svakih 30 s pogledaj je li karta slobodna, pa je zaključaj za sebe.
  function watchLock(id, me) {
    const l = ed.lock;
    l.beat = setInterval(async () => {
      if (ed.lock !== l) { clearInterval(l.beat); return; }
      const now = await readLock(id);
      if (lockState(now, me) !== 'other') {
        clearInterval(l.beat);
        if (ed.lock === l) claimLock(id, me);
      } else if (now?.who !== l.other?.who) { l.other = now; env.render(); }
    }, HEARTBEAT_MS);
  }

  function releaseLock() {
    const l = ed.lock;
    ed.lock = null;
    if (!l) return;
    clearInterval(l.beat);
    if (l.state !== 'mine' || !canWrite()) return;
    readLock(l.id).then(now => { if (now?.who === l.who) return fs.removeFile(store().root, lockPath(l.id)); }).catch(() => {});
  }
  window.addEventListener('beforeunload', () => releaseLock());

  // ---------- Traits & aliases ----------

  // Popis traitova (kartica Traits iz appa), svi tagovi na kartama s preimenovanjem, i aliasi heroja.
  function renderTraitsPage() {
    const counts = new Map();
    for (const c of allCards()) {
      (c.traits ?? []).forEach((t, i) => {
        if (!t) return;
        const row = counts.get(t) ?? { first: 0, other: 0 };
        if (i === 0 && PORTRAIT.includes(c.type)) row.first++; else row.other++;
        counts.set(t, row);
      });
    }
    const rows = [...counts.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const heroes = allCards().filter(c => c.type === 'Hero');
    return h('div', { class: 'ce-page' },
      env.renderTraits(),
      h('section', { class: 'panel' },
        h('h2', {}, 'Hero aliases'),
        h('p', { class: 'muted' }, 'Other names a card\'s first tag may use for a hero. Change them on the hero card.'),
        h('table', { class: 'ce-pub-table' }, h('tbody', {}, heroes.map(c => h('tr', {},
          h('td', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, c.name)), h('td', {}, (c.aliases ?? []).join(', ') || h('span', { class: 'muted' }, '–'))))))),
      h('section', { class: 'panel' },
        h('h2', {}, 'Tags on the cards'),
        h('p', { class: 'muted' }, 'Every tag on the cards. Renaming changes it on every card as drafts (Publish puts them into the game).'),
        h('table', { class: 'ce-pub-table' },
          h('thead', {}, h('tr', {}, ['Tag', 'First tag on', 'Other tag on', 'Rename to', ''].map(t => h('th', {}, t)))),
          h('tbody', {}, rows.map(([tag, n]) => {
            const to = h('input', { placeholder: tag });
            return h('tr', {}, h('td', {}, h('strong', {}, tag)), h('td', { class: 'num' }, n.first || '–'), h('td', { class: 'num' }, n.other || '–'), h('td', {}, to),
              h('td', {}, h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => renameTag(tag, to.value.trim())) }, 'Rename')));
          })))));
  }

  // Preimenovanje taga na svim kartama kao nacrti (karta kojoj se vrati objavljeni popis ostane bez nacrta za tagove).
  async function renameTag(from, to) {
    if (!to || to === from) throw new Error('Write the new name first.');
    const fresh = await readDrafts();
    fresh.cards ??= {};
    let n = 0;
    const ids = [...db().cards.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted).map(c => c.id),
      ...Object.entries(fresh.cards).filter(([id, d]) => d.new && !db().cards.some(c => c.id === id)).map(([id]) => id)];
    for (const c of ids.map(id => ({ id, ...(fresh.cards[id] ?? {}) }))) {
      const d = fresh.cards[c.id] ?? {};
      const traits = d.traits ?? db().cards.find(x => x.id === c.id)?.traits ?? c.traits ?? [];
      if (!traits.includes(from)) continue;
      const next = [...new Set(traits.map(t => (t === from ? to : t)))];
      const base = db().cards.find(x => x.id === c.id);
      const nd = { ...d, traits: next, updated: new Date().toISOString(), who: who() || undefined };
      if (base && sameVal(next, base.traits)) delete nd.traits;
      if (Object.keys(nd).every(k => k === 'updated' || k === 'who')) delete fresh.cards[c.id];
      else fresh.cards[c.id] = nd;
      n++;
    }
    if (!n) throw new Error(`No card has the tag ${from}.`);
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    const inList = (env.state.traits?.traits ?? []).some(t => t.name === from);
    env.toast(`${from} → ${to} on ${n} ${n === 1 ? 'card' : 'cards'} (drafts).${inList ? ` ${from} is on the trait list above: rename it there too.` : ''}`);
    env.render();
  }

  // ---------- objava ----------

  const draftList = () => Object.entries(ed.drafts?.cards ?? {})
    .map(([id, d]) => ({ id, d, base: db().cards.find(c => c.id === id) ?? null }))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

  // Razlike nacrta prema objavljenoj karti kao oznake (TEXT s riječima precrtano/zeleno, TAGS, FX, FRAME…).
  function changeChips(d, base) {
    const out = [];
    const card = { ...(base ?? {}), ...d };
    const chip = (label, ...body) => h('div', { class: 'ce-change' }, h('span', { class: 'ce-change-tag' }, label), h('span', {}, ...body));
    if (d.new) out.push(chip('NEW', 'new card'));
    if ('name' in d && base) out.push(chip('NAME', h('s', {}, base.name ?? ''), ' → ', h('span', { class: 'add' }, d.name ?? '')));
    if ('text' in d && base) out.push(chip('TEXT', ...wordDiff(base.text ?? '', d.text ?? '')));
    if ('traits' in d && base) {
      const a = base.traits ?? [];
      const b = d.traits ?? [];
      out.push(a[0] !== b[0] && PORTRAIT.includes(card.type) ? chip('TAGS', 'first tag ', h('s', {}, a[0] ?? '–'), ' → ', h('span', { class: 'add' }, b[0] ?? '–'))
        : chip('TAGS', b.filter(t => !a.includes(t)).map(t => `+${t}`).concat(a.filter(t => !b.includes(t)).map(t => `−${t}`)).join(' ')));
    }
    for (const k of ['cost', 'color', 'type', 'evo', 'hero', 'terrain']) if (k in d && base) out.push(chip(k.toUpperCase(), h('s', {}, String(base[k] ?? '–')), ' → ', h('span', { class: 'add' }, String(d[k] ?? '–'))));
    for (const k of ['stats', 'bonus']) if (k in d && base) out.push(chip(k.toUpperCase(), Object.entries(d[k] ?? {}).filter(([s, v]) => (base[k] ?? {})[s] !== v).map(([s, v]) => `${s.toUpperCase()} ${(base[k] ?? {})[s] ?? '–'} → ${v}`).join(', ') || 'changed'));
    if ('abilityNames' in d && base) out.push(chip('ABILITY', h('s', {}, base.abilityNames?.[0] ?? '–'), ' → ', h('span', { class: 'add' }, d.abilityNames?.[0] ?? '–')));
    if ('aliases' in d) out.push(chip('ALIASES', (d.aliases ?? []).join(', ')));
    if ('fx' in d || 'fxStatus' in d) out.push(chip('FX', d.fx ? `confirmed${d.who ? ` by ${d.who}` : ''}` : 'removed'));
    if (('art' in d || 'template' in d) && !base?.art) out.push(chip('FRAME', 'new frame (editor), art from Card Engine'));
    else if ('art' in d) out.push(chip('ART', 'new art'));
    else if ('artCrop' in d) out.push(chip('ART', 'art crop'));
    if ('emblem' in d || 'bg' in d) out.push(chip('PLATE', [d.emblem ? 'emblem' : null, d.bg ? `background ${d.bg}` : null].filter(Boolean).join(', ')));
    if ('coreImage' in d) out.push(chip('IMAGE', d.coreImage === 'effect' ? 'drawn from the effect' : 'uploaded'));
    if ('status' in d && Object.keys(d).length <= 4) out.push(chip('STATUS', d.status));
    return out;
  }

  function renderPublish() {
    const list = draftList();
    const marko = who() === 'Marko';
    const locked = id => ed.locks[id] && lockState(ed.locks[id], who()) === 'other';
    const selected = list.filter(x => !locked(x.id) && !ed.pubOff.has(x.id));
    const why = !canWrite() ? 'Publishing needs the shared folder (Chrome or Edge on a computer).'
      : !marko ? 'Only Marko publishes (Signed in as Marko).'
        : !ed.agency ? 'Agency FB is not on this computer: the card PNGs must be made on a computer that has it.'
          : !selected.length ? 'Nothing selected.' : null;
    const thumb = (card, px) => { const c = h('canvas', { class: 'ce-pub-thumb' }); thumbInto(c, card, px); return c; };
    const oldThumb = (base, px) => {
      const img = h('img', { class: 'ce-pub-thumb', alt: '' });
      img.style.width = `${px}px`;
      store().imageUrl(base, { thumb: true }).then(u => { if (u) img.src = u; });
      return img;
    };
    const rows = list.map(({ id, d, base }) => {
      const card = { ...(base ?? {}), ...d, id };
      const px = HEROISH.includes(card.type) ? 168 : 120;
      if (locked(id)) {
        const l = ed.locks[id];
        return h('div', { class: 'ce-pub-row locked' },
          h('span', { class: 'ce-pub-check' }, '🔒'),
          h('div', { class: 'ce-pub-imgs' }, h('figure', {}, thumb(card, px))),
          h('div', { class: 'ce-pub-body' }, h('h3', {}, card.name || id, h('small', {}, ` ${id}`)),
            h('p', { class: 'warn' }, `${l.who} is editing it now. It can be published after they save and close it.`)));
      }
      return h('div', { class: 'ce-pub-row' },
        h('label', { class: 'ce-pub-check' }, h('input', { type: 'checkbox', checked: !ed.pubOff.has(id), onchange: e => { if (e.target.checked) ed.pubOff.delete(id); else ed.pubOff.add(id); env.render(); } })),
        h('div', { class: 'ce-pub-imgs' },
          base?.image ? h('figure', {}, oldThumb(base, px), h('figcaption', { class: 'muted small' }, 'Published')) : null,
          base?.image ? h('span', { class: 'ce-arrow' }, '→') : null,
          h('figure', {}, thumb(card, px), h('figcaption', { class: 'muted small' }, 'New'))),
        h('div', { class: 'ce-pub-body' },
          h('h3', {}, card.name || id, h('small', {}, ` ${id}`)),
          h('p', { class: 'muted small' }, `${d.who || '–'} · ${when(d.updated)}`),
          ...changeChips(d, base),
          !card.art && card.type !== 'Core' ? h('p', { class: d.new ? 'warn small' : 'muted small' }, d.new ? 'No art: a new card waits until it has art.' : 'No art: the old picture stays.') : null),
        h('button', { class: 'link accent', type: 'button', onclick: () => go(id) }, 'Open in editor'));
    });
    return h('div', { class: 'ce-page ce-publish' },
      h('header', { class: 'ce-page-head' },
        h('div', {}, h('h1', {}, 'Publish'), h('p', { class: 'muted' }, 'Changes saved in the editor. The game sees them only after you publish.')),
        h('div', { class: 'ce-page-actions' },
          sets.newCardButton(sets.current() ?? 'OP1', ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist'], 'ghost'),
          h('button', { class: 'publish', type: 'button', disabled: !!why, title: why ?? '', onclick: () => env.guard(() => publishAll(selected.map(x => x.id))) }, `Publish ${selected.length} ${selected.length === 1 ? 'card' : 'cards'}`))),
      why && list.length ? h('p', { class: 'muted small' }, why) : null,
      renderLast(marko),
      list.length ? rows : h('p', { class: 'muted' }, 'Nothing waits for Publish.'));
  }

  // Riječi koje su otpale precrtane, nove zelene; isti dio sažet na "…" s ponešto riječi oko izmjene.
  function wordDiff(a, b) {
    const x = a.split(/\s+/).filter(Boolean);
    const y = b.split(/\s+/).filter(Boolean);
    const m = x.length;
    const n = y.length;
    const L = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
    for (let i = m - 1; i >= 0; i--) for (let j = n - 1; j >= 0; j--) L[i][j] = x[i] === y[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    const ops = [];
    let i = 0;
    let j = 0;
    while (i < m || j < n) {
      if (i < m && j < n && x[i] === y[j]) { ops.push(['=', x[i]]); i++; j++; } else if (j < n && (i >= m || L[i][j + 1] >= L[i + 1][j])) { ops.push(['+', y[j]]); j++; } else { ops.push(['-', x[i]]); i++; }
    }
    const keep = new Set();
    ops.forEach((o, k) => { if (o[0] !== '=') for (let d = -3; d <= 3; d++) keep.add(k + d); });
    const out = [];
    let gap = false;
    ops.forEach((o, k) => {
      if (!keep.has(k)) { if (!gap && out.length) out.push('… '); gap = true; return; }
      if (gap && !out.length) out.push('… ');
      gap = false;
      out.push(o[0] === '=' ? `${o[1]} ` : h(o[0] === '+' ? 'span' : 's', { class: o[0] === '+' ? 'add' : '' }, o[1]), o[0] === '=' ? null : ' ');
    });
    if (gap) out.push('…');
    return out.filter(v => v !== null);
  }

  async function readLast() {
    return readJson(LAST_PUBLISH_PATH, null);
  }

  // Zadnja Objava i Undo (samo Marko, dok se baza nije mijenjala).
  function renderLast(marko) {
    if (!canWrite()) return null;
    if (ed.last === undefined) {
      ed.last = null;
      readLast().then(l => { ed.last = l ?? false; if (l) env.render(); });
      return null;
    }
    const l = ed.last;
    if (!l) return null;
    const ok = db().updated === l.after.updated;
    return h('div', { class: 'ce-last' },
      h('span', { class: 'small' }, `Last Publish: ${new Date(l.at).toLocaleString()}${l.who ? ` by ${l.who}` : ''}, ${Object.keys(l.drafts).length} cards${l.bumped ? `, version ${l.after.version}` : ''}.`),
      ok ? h('button', { class: 'ghost', type: 'button', disabled: !marko, onclick: () => env.guard(undoPublish) }, 'Undo last Publish')
        : h('small', { class: 'muted' }, 'Cards changed since then, so it can no longer be undone.'));
  }

  // Undo zadnje Objave: baza kakva je bila prije nje (pod novom verzijom, da igra i deckovi vide promjenu),
  // nove slike van, objavljeni nacrti opet čekaju. Samo dok se baza u međuvremenu nije mijenjala.
  async function undoPublish() {
    await env.assertFresh();
    const last = await readLast();
    if (!last) throw new Error('No Publish to undo.');
    if (db().updated !== last.after.updated) throw new Error('The cards changed after that Publish (Import or another save), so it can no longer be undone.');
    if (!confirm(`Undo the Publish of ${new Date(last.at).toLocaleString()} (${Object.keys(last.drafts).length} cards)? The cards go back to how they were and wait as drafts again.`)) return;
    const restored = { ...last.before, version: db().version + (last.bumped ? 1 : 0), updated: new Date().toISOString() };
    await env.commitDb(restored);
    const after = await readDrafts();
    after.cards ??= {};
    for (const [id, d] of Object.entries(last.drafts)) after.cards[id] = after.cards[id] ? { ...d, ...after.cards[id] } : d;
    const files = await fs.listFileNames(store().root, 'data/images').catch(() => []);
    for (const [id, d] of Object.entries(last.drafts)) {
      if (!d.new) continue;
      for (const name of files.filter(n => n.startsWith(`${id}.`))) await fs.removeFile(store().root, `data/images/${name}`).catch(() => {});
    }
    await writeJson(DRAFTS_PATH, after);
    await fs.removeFile(store().root, LAST_PUBLISH_PATH).catch(() => {});
    ed.drafts = after;
    ed.last = false;
    for (const id of Object.keys(last.drafts)) await logHistory(id, 'Publish undone').catch(() => {});
    env.toast(`Publish undone: ${Object.keys(last.drafts).length} cards are drafts again${last.bumped ? ` (version ${restored.version})` : ''}.`);
    env.render();
  }

  // Objava odabranih nacrta: PNG svake karte s artom (renderer), baza i povijest (env.commitDb), nacrti van.
  // Karta bez arta zadržava staru sliku (Card Engine PNG); nova karta bez arta čeka.
  async function publishAll(ids) {
    await env.assertFresh();
    const fresh = await readDrafts();
    await readLocks();
    const drafts = {};
    for (const id of ids) if (fresh.cards?.[id] && !ed.locks[id]) drafts[id] = fresh.cards[id];
    const list = Object.keys(drafts);
    if (!list.length) throw new Error('Nothing to publish.');
    if (!confirm(`Publish ${list.length} ${list.length === 1 ? 'card' : 'cards'} into the game?`)) return;
    const before = db();
    const images = {};
    const kept = [];
    for (const id of list) {
      const base = db().cards.find(c => c.id === id) ?? (drafts[id].new ? { id } : null);
      if (!base) continue;
      const card = { ...base, ...drafts[id] };
      const core = card.type === 'Core' && coreMode(card) === 'effect';
      const url = card.art ? await store().dataUrl(card.art) : null;
      const art = url ? await loadImage(url).catch(() => null) : null;
      if (!art && !core) { if (drafts[id].new) delete drafts[id]; kept.push(id); continue; }
      const heroOfCard = card.type === 'Evolution' ? db().cards.find(x => x.type === 'Hero' && x.name === card.hero) : null;
      const emblemPath = card.emblem ?? (heroOfCard ? drafts[heroOfCard.id]?.emblem ?? heroOfCard.emblem : null);
      const eUrl = emblemPath ? await store().dataUrl(emblemPath) : null;
      const emblem = eUrl ? await loadImage(eUrl).catch(() => null) : null;
      const canvas = document.createElement('canvas');
      renderCard(canvas, card, await templateFor(card), art, emblem);
      const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const hash = await imageHashOf(bytes);
      if (hash === base.imageHash) continue;
      await fs.writeFile(store().root, `data/images/${id}.${hash}.png`, bytes);
      images[id] = hash;
    }
    const { db: next, changed, bumped } = applyDrafts(db(), drafts, images);
    if (changed) {
      // Nova Objava zamjenjuje zadnju: Undo prethodne više nije moguć, pa njene stare slike mogu van.
      await env.dropOldImages();
      await env.commitDb(next, { keepOld: true });
      await writeJson(LAST_PUBLISH_PATH, { at: new Date().toISOString(), who: who(), bumped, after: { version: next.version, updated: next.updated }, drafts, before });
      ed.last = undefined;
    }
    // Nacrti spremljeni dok je Objava trajala ostaju za iduću.
    const after = await readDrafts();
    for (const id of Object.keys(drafts)) if (after.cards?.[id]?.updated === drafts[id].updated) delete after.cards[id];
    await writeJson(DRAFTS_PATH, after);
    ed.drafts = after;
    for (const id of Object.keys(drafts)) await logHistory(id, `published${bumped ? ` v${next.version}` : ''}`).catch(() => {});
    const parts = [`${changed} ${changed === 1 ? 'card' : 'cards'}`, `${Object.keys(images).length} new PNGs`];
    if (kept.length) parts.push(`no art yet (old picture kept, new cards wait): ${kept.join(', ')}`);
    env.toast(`Published${bumped ? ` (version ${next.version})` : changed ? ' (look only)' : ''}: ${parts.join(', ')}. Next: fx proposals for the game (ask Claude Code to run them).`);
    env.render();
  }

  // ---------- podstranice ----------

  const guide = createGuideView({ h, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, onSaved: g => { ed.guide = g; } });
  // Spremljen okvir: editor ga učita iznova, sličice se crtaju iznova.
  const frames = createFramesView({ h, state: env.state, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, drafts: () => ed.drafts, onSaved: name => { delete ed.tpls[name]; ed.thumbs.clear(); } });
  const sets = createSetsView({
    h, state: env.state, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast,
    cards: allCards, drafts: () => ed.drafts, locks: () => ed.locks, thumbInto, go: id => go(id), newCard, nextId,
  });

  return {
    render, isCardPage, isDirty: () => ed.dirty, newCard, who, setWho, leave,
    waiting: () => Object.keys(ed.drafts?.cards ?? {}).length,
    wishes: () => (ed.wishlist?.items ?? []).filter(i => i.status === 'open').length,
  };
}
