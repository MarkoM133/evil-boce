// Testovi parsera i uvoza na izmišljenim kartama (repo je javan, prave karte su u docs/private).
// Pokretanje: node --test test/
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCardEngineXml, cleanText } from '../js/parse.js';
import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, emptyDb, normalizeDb, thumbPlan, archiveFolder, archivePath, emptyChangelog, changelogEntry, appendChangelog, changesSince, describeChange, publishedPngPaths } from '../js/importer.js';
import { deckChanges } from '../js/deck.js';

const RGB = { Cyan: [0, 255, 255], Red: [255, 0, 0], White: [255, 255, 255], Odd: [10, 20, 30] };
const ICON = { kb: 24, pwr: 25, rng: 26, dmg: 27, hp: 28 };

function el(kind, t, x, y, rgb = [255, 255, 255], active = true) {
  const esc = String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return `<Element><ID>1</ID><Tag /><Active>${active}</Active><SizeDelta><x>1</x><y>1</y></SizeDelta>
    <Position><x>${x}</x><y>${y}</y></Position><Text>${esc}</Text><font />
    <color><r>${rgb[0]}</r><g>${rgb[1]}</g><b>${rgb[2]}</b><a>255</a></color>
    <Type>${kind === 'text' ? 0 : 1}</Type></Element>`;
}

function card({ name, code, type, color = 'Cyan', cost, evo, icons = {}, traits, text, extra = [] }) {
  const els = [el('image', 'frame_2', 0, 0)];
  if (color) els.push(el('image', 'p_frame_11', 0, 0, RGB[color]));
  els.push(el('text', name, 0, 460.97));
  if (code) els.push(el('text', code, 300, -480));
  if (type) els.push(el('text', type, -212.5, -150));
  if (cost !== undefined) els.push(el('text', cost, 283, 461));
  if (evo !== undefined) els.push(el('text', evo, -297, 461));
  let row = 0;
  for (const [k, v] of Object.entries(icons)) {
    const y = -60 - 40 * row++;
    els.push(el('image', `tabletop_icons_${ICON[k]}`, -60, y));
    els.push(el('text', v, 40, y + 1));
    els.push(el('text', '99', 200, y));
  }
  if (traits) els.push(el('text', traits, 158.00006, -456.31));
  if (text !== undefined) els.push(el('text', text, 0, -300));
  els.push(...extra);
  return `<Card><ID>123</ID><Quantity>1</Quantity><Name>${name}</Name><TemplateID>9</TemplateID>
    <Front><useMask>true</useMask><Elements>${els.join('')}</Elements></Front><Back /></Card>`;
}

const xml = (...cards) => `<?xml version="1.0" encoding="utf-8"?>\n<ArrayOfCard xmlns:xsd="x">${cards.join('')}</ArrayOfCard>`;

const HERO = { name: 'Hero A', code: 'OP9-001', type: 'Hero', icons: { hp: '8', dmg: '3', pwr: '3000', rng: '4', kb: '3' }, traits: 'Crew/Fruit', text: '<sprite=3 color=#00FFFF><b>Postroll:</b> Hero A heals 2<sprite=0 color=#00FF00>.' };
const ACTION = { name: 'Punch', code: 'OP9-002', type: 'Action', cost: '1', icons: { pwr: '+2000' }, traits: 'Hero A', text: '<b>Battle Phase:</b>' };
const EVO = { name: 'Hero A, Big Form', code: 'OP9-003', type: 'Evolution', cost: '2', evo: '1', icons: { hp: '10', dmg: '3', pwr: '4000', rng: '4', kb: '3' }, traits: 'Crew', text: 'x' };
const STAGE = { name: 'Island', code: 'Stage-009', color: null, text: 'When revealed.' };
const TOKEN = { name: '+2 Damage', color: null, text: '+2 <sprite=1>' };

const png = (bytes, path, lastModified = 1) => ({ path, lastModified, getBytes: async () => new Uint8Array(bytes) });

test('cleanText: sprite, bold i vodeći Range', () => {
  assert.equal(cleanText(HERO.text), '[Range] Postroll: Hero A heals 2 HP.');
  assert.equal(cleanText('Gains +1000<sprite=2 color=#FFFF00> now .'), 'Gains +1000 Power now.');
});

test('parser: Hero, Action, Evolution, Stage, token', () => {
  const r = parseCardEngineXml(xml(card(HERO), card(ACTION), card(EVO), card(STAGE), card(TOKEN)));
  assert.equal(r.length, 5);
  const [h, a, e, s, t] = r;
  assert.deepEqual(h.card, {
    id: 'OP9-001', name: 'Hero A', type: 'Hero', color: 'Cyan',
    stats: { hp: 8, dmg: 3, pwr: 3000, rng: 4, kb: 3 },
    traits: ['Crew', 'Fruit'], text: '[Range] Postroll: Hero A heals 2 HP.',
  });
  assert.deepEqual(h.problems, []);
  assert.deepEqual(a.card, { id: 'OP9-002', name: 'Punch', type: 'Action', color: 'Cyan', cost: 1, bonus: { pwr: 2000 }, traits: ['Hero A'], text: 'Battle Phase:' });
  assert.equal(e.card.hero, 'Hero A');
  assert.equal(e.card.evo, 1);
  assert.equal(e.card.cost, 2);
  assert.equal(e.card.stats.pwr, 4000);
  assert.equal(s.card.type, 'Stage');
  assert.equal(s.card.color, null);
  assert.deepEqual(s.problems, []);
  assert.equal(t.skip, true);
});

test('parser: vrijednosti bez predznaka idu u values', () => {
  const [r] = parseCardEngineXml(xml(card({ ...ACTION, icons: { kb: '3', rng: '3', dmg: '-2' } })));
  assert.deepEqual(r.card.bonus, { dmg: -2 });
  assert.deepEqual(r.card.values, { rng: 3, kb: 3 });
  assert.equal(r.problems[0].level, 'warn');
});

test('parser: greške (kod, boja, cost, statsi)', () => {
  const r = parseCardEngineXml(xml(
    card({ ...ACTION, code: 'OP-032' }),
    card({ ...ACTION, code: 'OP9-010', color: 'White' }),
    card({ ...ACTION, code: 'OP9-011', color: 'Odd' }),
    card({ ...ACTION, code: 'OP9-012', cost: undefined }),
    card({ ...HERO, code: 'OP9-013', icons: { hp: '8' } }),
    card({ ...ACTION, code: 'OP9-014', type: undefined }),
  ));
  const msgs = r.map(x => x.problems.filter(p => p.level === 'error').map(p => p.msg).join(' | '));
  assert.match(msgs[0], /doesn't match the pattern/);
  assert.match(msgs[1], /unknown frame tint/);
  assert.match(msgs[2], /unknown frame tint/);
  assert.match(msgs[3], /no cost/);
  assert.match(msgs[4], /missing stats: dmg, pwr, rng, kb/);
  assert.match(msgs[5], /no card type/);
});

test('parser: neaktivni elementi se ignoriraju', () => {
  const [r] = parseCardEngineXml(xml(card({ ...ACTION, extra: [el('text', 'Equipment', -212.5, -150, undefined, false)] })));
  assert.equal(r.card.type, 'Action');
});

// Novi landscape Hero / Evolution (2026-10-24): elementi po SiblingIndexu, okvir *_hero_frame_X / *_evo_frame_X.
function lel(idx, kind, t, x, y, rgb = [255, 255, 255], rotation = 0) {
  const esc = String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return `<Element><ID>1</ID><Tag /><Active>true</Active><SizeDelta><x>1</x><y>1</y></SizeDelta>
    <Position><x>${x}</x><y>${y}</y></Position><Text>${esc}</Text><font /><rotation>${rotation}</rotation>
    <color><r>${rgb[0]}</r><g>${rgb[1]}</g><b>${rgb[2]}</b><a>255</a></color>
    <Type>${kind === 'text' ? 0 : 1}</Type><SiblingIndex>${idx}</SiblingIndex></Element>`;
}

function landCard({ name, code, label, frame, stats, traits, text, cost, rot = false }) {
  const els = [
    [0, 'image', `Custom_${code} ${name}`, -286, 0],
    [1, 'image', frame, 0, 0],
    [2, 'image', `Custom_${code} ${name} Logo`, 19, 295],
    [3, 'text', `<b><cspace=6>${label}</cspace></b>`, 256.5, 325],
    [4, 'text', `<b>${name}</b>`, 256.5, 290],
    [5, 'image', 'tabletop_icons_28', 26, 200], [6, 'text', stats.hp, 76, 200],
    [7, 'image', 'tabletop_icons_27', 201, 200], [8, 'text', stats.dmg, 251, 200],
    [9, 'image', 'tabletop_icons_25', 356, 200], [10, 'text', stats.pwr, 420, 200],
    [11, 'text', text, 226.5, -1],
    [12, 'image', 'tabletop_icons_26', -9, -305], [13, 'text', stats.rng, 38, -305],
    [14, 'image', 'tabletop_icons_24', 88, -305], [15, 'text', stats.kb, 139, -305],
    [16, 'text', traits, 346, -304],
    [17, 'text', `<b>${code}</b>`, 483, -367],
    ...(cost !== undefined ? [[18, 'text', cost, 434, 295]] : []),
  ].map(([i, k, t, x, y]) => (rot ? lel(i, k, t, -y, x, undefined, 90) : lel(i, k, t, x, y)));
  const cardName = rot ? `${code} ${name} (rot)` : label === 'HERO' ? `${code} ${name} Hero` : `${code} ${name}`;
  return `<Card><ID>1</ID><Quantity>1</Quantity><Name>${cardName}</Name><TemplateID>9</TemplateID>
    <Front><useMask>true</useMask><Elements>${els.join('')}</Elements></Front><Back /></Card>`;
}

const LHERO = { name: 'Hero B', code: 'OP9-020', label: 'HERO', frame: 'Hero_templates_hero_frame_M', stats: { hp: '10', dmg: '4', pwr: '2000', rng: '3', kb: '3' }, traits: 'Crew/Stand', text: '<sprite=3 color=#00FFFF><b>Postroll:</b> heal 2.' };
const LEVO = { name: 'Hero B, Requiem', code: 'OP9-021', label: 'EVOLUTION II', frame: 'EvoFrames_evo_frame_M', stats: { hp: '10', dmg: '5', pwr: '3000', rng: '3', kb: '3' }, traits: 'Crew', text: 'Big.', cost: '5' };

test('parser: landscape Hero i Evolution (SiblingIndex, boja iz okvira, rimski stupanj)', () => {
  const [h, e] = parseCardEngineXml(xml(landCard(LHERO), landCard(LEVO)));
  assert.deepEqual(h.card, {
    id: 'OP9-020', name: 'Hero B', type: 'Hero', color: 'Purple',
    stats: { hp: 10, dmg: 4, pwr: 2000, rng: 3, kb: 3 }, traits: ['Crew', 'Stand'], text: '[Range] Postroll: heal 2.', landscape: true,
  });
  assert.deepEqual(h.problems, []);
  assert.equal(h.variant, null);
  assert.deepEqual([e.card.type, e.card.cost, e.card.evo, e.card.hero, e.card.color], ['Evolution', 5, 2, 'Hero B', 'Purple']);
  assert.deepEqual(e.problems, []);
});

test('parser: rotirana verzija (rot) je ista karta, variant rot', () => {
  const [land] = parseCardEngineXml(xml(landCard(LEVO)));
  const [rot] = parseCardEngineXml(xml(landCard({ ...LEVO, rot: true })));
  assert.equal(rot.variant, 'rot');
  assert.deepEqual(rot.card, land.card);
});

test('parser: stari layout s labelom Character daje Hero', () => {
  const [h] = parseCardEngineXml(xml(card({ ...HERO, type: 'Character' })));
  assert.equal(h.card.type, 'Hero');
});

async function firstImport() {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/all.xml', text: xml(card(HERO), card(ACTION), card(EVO), card(STAGE), card(TOKEN)), lastModified: 1 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([2], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([4], 'export/Island.png'), png([5], 'export/+2 Damage.png')],
    db: emptyDb(),
  });
  return { a, pub: buildPublish(emptyDb(), a, new Date('2026-10-22T10:00:00Z')) };
}

test('uvoz u praznu bazu', async () => {
  const { a, pub } = await firstImport();
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => e.status), ['new', 'new', 'new', 'new']);
  assert.ok(a.infos.some(i => /tokens/.test(i.msg)));
  assert.ok(a.infos.some(i => /\+2 Damage\.png/.test(i.msg)));
  assert.equal(pub.db.version, 1);
  assert.equal(pub.writes.length, 4);
  const hero = pub.db.cards.find(c => c.id === 'OP9-001');
  assert.equal(hero.wt, 2);
  assert.equal(hero.bakugan, 'Hero A');
  assert.equal(hero.rev, 1);
  assert.equal(hero.deleted, false);
  assert.match(hero.image, /^images\/OP9-001\.[0-9a-f]{8}\.png$/);
  assert.deepEqual(Object.keys(hero), ['id', 'name', 'type', 'color', 'stats', 'wt', 'traits', 'text', 'bakugan', 'image', 'imageHash', 'rev', 'deleted']);
  assert.equal(pub.db.cards.find(c => c.id === 'OP9-002').wt, undefined);
});

test('djelomični uvoz: promjena, ista karta, karta koje nema ostaje, app polja ostaju', async () => {
  const { pub } = await firstImport();
  const edited = applyAppEdits(pub.db, { 'OP9-001': { wt: 3, bakugan: 'Ball A' } }).db;
  assert.equal(edited.version, 2);
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/edit.xml', text: xml(card({ ...HERO, icons: { ...HERO.icons, hp: '9' } }), card(ACTION)), lastModified: 5 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([9], 'export/Punch.png')],
    db: edited,
  });
  assert.deepEqual(a.errors, []);
  const [h, p] = a.entries;
  assert.equal(h.status, 'changed');
  assert.deepEqual(h.diffs, ['stats']);
  assert.equal(h.imageChanged, false);
  assert.equal(p.status, 'changed');
  assert.deepEqual(p.diffs, []);
  assert.equal(p.imageChanged, true);
  const next = buildPublish(edited, a).db;
  assert.equal(next.version, 3);
  assert.equal(next.cards.length, 4);
  const hero = next.cards.find(c => c.id === 'OP9-001');
  assert.equal(hero.stats.hp, 9);
  assert.equal(hero.wt, 3);
  assert.equal(hero.bakugan, 'Ball A');
  assert.equal(hero.rev, 3);
  assert.equal(next.cards.find(c => c.id === 'OP9-003').rev, 1);
});

test('isti uvoz drugi put ne mijenja verziju', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/all.xml', text: xml(card(HERO), card(ACTION), card(EVO), card(STAGE)), lastModified: 1 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([2], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([4], 'export/Island.png')],
    db: pub.db,
  });
  assert.ok(a.entries.every(e => e.status === 'same'));
  assert.equal(buildPublish(pub.db, a).changed, 0);
});

test('ista karta u dva XML-a: vrijedi noviji', async () => {
  const a = await analyzeExport({
    xmlFiles: [
      { path: 'export/new.xml', text: xml(card({ ...ACTION, cost: '3' })), lastModified: 9 },
      { path: 'export/old.xml', text: xml(card(ACTION)), lastModified: 1 },
    ],
    pngFiles: [png([2], 'export/Punch.png')],
    db: emptyDb(),
  });
  assert.equal(a.entries[0].card.cost, 3);
  assert.ok(a.warnings.some(w => /newer export\/new\.xml/.test(w.msg)));
});

test('provjere: dupla imena, Evolution bez heroja, bez PNG-a', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(EVO), card(ACTION), card({ ...ACTION, code: 'OP9-020' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png')],
    db: emptyDb(),
  });
  const msgs = a.errors.map(e => `${e.id}: ${e.msg}`).join('\n');
  assert.match(msgs, /OP9-003: new card without a PNG/);
  assert.match(msgs, /OP9-002: PNG "Punch.png": unclear which card it belongs to/);
  assert.match(msgs, /hero "Hero A" doesn't exist/);
});

test('promijenjena karta bez PNG-a zadržava staru sliku', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [],
    db: pub.db,
  });
  assert.deepEqual(a.errors, []);
  assert.match(a.warnings[0].msg, /the old image stays/);
  const next = buildPublish(pub.db, a);
  assert.equal(next.writes.length, 0);
  const old = pub.db.cards.find(c => c.id === 'OP9-002');
  assert.equal(next.db.cards.find(c => c.id === 'OP9-002').image, old.image);
});

test('obsoleteImages: briše se tek kad nova verzija ima Steam URL', () => {
  const db = { version: 1, cards: [{ id: 'OP9-001', imageHash: 'bbbbbbbb' }] };
  const files = ['OP9-001.aaaaaaaa.png', 'OP9-001.bbbbbbbb.png'];
  assert.deepEqual(obsoleteImages(db, files, {}), []);
  assert.deepEqual(obsoleteImages(db, files, { 'OP9-001.bbbbbbbb': 'https://x' }), ['OP9-001.aaaaaaaa.png']);
});

test('thumbPlan: nedostajuće i stare sličice', () => {
  const db = { cards: [{ id: 'OP9-001', image: 'images/OP9-001.bbbbbbbb.png', imageHash: 'bbbbbbbb' }, { id: 'OP9-002', image: 'images/OP9-002.cccccccc.png', imageHash: 'cccccccc' }, { id: 'X', image: null, imageHash: null }] };
  const plan = thumbPlan(db, ['OP9-001.aaaaaaaa.jpg', 'OP9-002.cccccccc.jpg']);
  assert.deepEqual(plan.missing.map(c => c.id), ['OP9-001']);
  assert.deepEqual(plan.extra, ['OP9-001.aaaaaaaa.jpg']);
});

test('sanduče: arhiva po datumu, ista struktura podfoldera', () => {
  const folder = archiveFolder(new Date(2026, 9, 23, 9, 5));
  assert.equal(folder, 'export/objavljeno/2026-10-23 09.05');
  assert.equal(archivePath('export/Nove/Luffy.png', folder), 'export/objavljeno/2026-10-23 09.05/Nove/Luffy.png');
  assert.equal(archivePath('export/a.xml', folder), 'export/objavljeno/2026-10-23 09.05/a.xml');
});

test('prazan export/: nema grešaka ni promjena', async () => {
  const a = await analyzeExport({ xmlFiles: [], pngFiles: [], db: emptyDb() });
  assert.deepEqual([a.entries, a.errors, a.warnings], [[], [], []]);
});

test('promijenjeni podaci, a isti PNG: upozorenje da je slika možda stara', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png')],
    db: pub.db,
  });
  const e = a.entries.find(x => x.id === 'OP9-002');
  assert.equal(e.status, 'changed');
  assert.equal(e.staleImage, true);
  assert.match(a.warnings.map(w => w.msg).join('\n'), /changed \(cost\), but the PNG is the same as before; the image may be outdated/);
  const fresh = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [png([9], 'export/Punch.png')],
    db: pub.db,
  });
  assert.equal(fresh.entries.find(x => x.id === 'OP9-002').staleImage, false);
  assert.deepEqual(fresh.warnings, []);
});

test('sam PNG bez XML-a: nova slika postojeće karte po imenu', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({ xmlFiles: [], pngFiles: [png([9], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([7], 'export/Nepoznato.png')], db: pub.db });
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => [e.id, e.status, e.imageChanged]), [['OP9-002', 'changed', true], ['OP9-003', 'same', false]]);
  assert.ok(a.infos.some(i => /Nepoznato\.png/.test(i.msg)));
  const next = buildPublish(pub.db, a);
  const old = pub.db.cards.find(c => c.id === 'OP9-002');
  const now = next.db.cards.find(c => c.id === 'OP9-002');
  assert.notEqual(now.imageHash, old.imageHash);
  assert.equal(now.rev, old.rev + 1);
  for (const k of ['name', 'type', 'cost', 'text', 'traits']) assert.deepEqual(now[k], old[k]);
  assert.equal(next.writes.length, 1);
});

test('povijest: zapis po verziji, promjene od verzije, promjene u decku', async () => {
  const { pub } = await firstImport();
  let log = appendChangelog(emptyChangelog(), changelogEntry(emptyDb(), pub.db));
  assert.equal(log.entries[0].version, 1);
  assert.deepEqual(log.entries[0].cards.map(c => c.kind), ['new', 'new', 'new', 'new']);

  // v2: Punch dobije novi cost i sliku; v3: Island maknut (app polje).
  const a = await analyzeExport({ xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }], pngFiles: [png([9], 'export/Punch.png')], db: pub.db });
  const v2 = buildPublish(pub.db, a, new Date('2026-10-23T10:00:00Z')).db;
  log = appendChangelog(log, changelogEntry(pub.db, v2));
  const v3 = applyAppEdits(v2, { 'Stage-009': { deleted: true } }).db;
  log = appendChangelog(log, changelogEntry(v2, v3));
  assert.deepEqual(log.entries.map(e => e.version), [1, 2, 3]);
  assert.deepEqual(log.entries[1].cards, [{ id: 'OP9-002', name: 'Punch', kind: 'changed', fields: ['cost'], image: true }]);
  assert.equal(describeChange(log.entries[1].cards[0]), 'cost, image');
  assert.equal(describeChange(log.entries[2].cards[0]), 'deleted');

  // Bez promjena nema novog zapisa.
  assert.equal(appendChangelog(log, changelogEntry(v3, v3)), log);

  const since1 = changesSince(log, 1);
  assert.deepEqual([...since1.keys()], ['OP9-002', 'Stage-009']);
  assert.deepEqual([...changesSince(log, 2).keys()], ['Stage-009']);

  const deck = { heroes: ['OP9-001'], cards: { 'OP9-002': 2, 'OP9-003': 0 } };
  assert.deepEqual(deckChanges(deck, since1).map(x => [x.id, x.changes.map(c => c.version)]), [['OP9-002', [2]]]);
  assert.deepEqual(deckChanges(deck, changesSince(log, 0)), [{ id: 'OP9-002', changes: [{ version: 2, kind: 'changed', fields: ['cost'], image: true }] }]);
});

test('kodovi drugih setova: DBZ-015, JJ5-001 i OPM-001 su ispravni, OP bez broja seta nije', () => {
  const parsed = parseCardEngineXml(xml(card({ ...ACTION, code: 'DBZ-015' }), card({ ...ACTION, name: 'Kick', code: 'JJ5-001' }), card({ ...ACTION, name: 'Punch!', code: 'OPM-001' }), card({ ...ACTION, name: 'Bad', code: 'OP-033' })));
  assert.deepEqual(parsed.map(p => [p.code, p.problems.filter(x => x.level === 'error').length]), [['DBZ-015', 0], ['JJ5-001', 0], ['OPM-001', 0], ['OP-033', 1]]);
});

test('PNG "KOD Ime.png": isto ime u dva seta, svaka karta svoju sliku', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card({ ...ACTION, code: 'DBZ-002', color: 'Red' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/OP9-002 Punch.png'), png([7], 'export/DBZ/DBZ-002 Punch.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
  assert.match(a.warnings.map(w => w.msg).join('\n'), /same name "Punch" is used by DBZ-002, OP9-002; that's allowed/);
  assert.deepEqual(a.entries.map(e => [e.id, e.png.path]), [['DBZ-002', 'export/DBZ/DBZ-002 Punch.png'], ['OP9-002', 'export/OP9-002 Punch.png']]);
  assert.notEqual(a.entries[0].imageHash, a.entries[1].imageHash);
});

test('PNG s kodom ima prednost pred PNG-om s imenom; i sam kod je dovoljan', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card(HERO)), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png'), png([3], 'export/OP9-002 Punch.png'), png([1], 'export/OP9-001.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => [e.id, e.png.path]), [['OP9-001', 'export/OP9-001.png'], ['OP9-002', 'export/OP9-002 Punch.png']]);
  assert.match(a.infos.map(i => i.msg).join('\n'), /skipped 1 PNG.*Punch\.png/);
});

test('heroj s istim imenom kao druga karta je greška', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(HERO), card({ ...ACTION, name: 'Hero A', code: 'DBZ-003' })), lastModified: 1 }],
    pngFiles: [png([1], 'export/OP9-001 Hero A.png'), png([2], 'export/DBZ-003 Hero A.png')],
    db: emptyDb(),
  });
  assert.match(a.errors.map(e => e.msg).join('\n'), /name "Hero A" is used by .*a hero must have a unique name/);
});

test('sam PNG: po kodu radi uvijek, po imenu samo kad je ime jednoznačno', async () => {
  const first = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card({ ...ACTION, code: 'DBZ-002', color: 'Red' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/OP9-002 Punch.png'), png([7], 'export/DBZ-002 Punch.png')],
    db: emptyDb(),
  });
  const db = buildPublish(emptyDb(), first).db;
  const byCode = await analyzeExport({ xmlFiles: [], pngFiles: [png([8], 'export/DBZ-002 Punch.png')], db });
  assert.deepEqual(byCode.errors, []);
  assert.deepEqual(byCode.entries.map(e => [e.id, e.status, e.imageChanged]), [['DBZ-002', 'changed', true]]);
  const byName = await analyzeExport({ xmlFiles: [], pngFiles: [png([8], 'export/Punch.png')], db });
  assert.match(byName.errors.map(e => e.msg).join('\n'), /DBZ-002 and OP9-002 share the same name; the PNG must start with the code/);
  assert.deepEqual(byName.entries, []);
});

test('sprite: uz heroja iz XML-a, sam za postojećeg, Evolution bez razmaka iza zareza', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(HERO)), lastModified: 1 }],
    pngFiles: [png([1], 'export/OP9-001 Hero A.png'), png([11], 'export/OP9-001 Hero A Sprite.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
  assert.equal(a.entries[0].png.path, 'export/OP9-001 Hero A.png');
  assert.equal(a.entries[0].spritePng.path, 'export/OP9-001 Hero A Sprite.png');
  const pub = buildPublish(emptyDb(), a);
  const hero = pub.db.cards[0];
  assert.match(hero.sprite, /^sprites\/OP9-001\.[0-9a-f]{8}\.png$/);
  assert.deepEqual(pub.writes.map(w => w.path).sort(), [`data/${hero.image}`, `data/${hero.sprite}`].sort());

  const { pub: base } = await firstImport();
  const only = await analyzeExport({ xmlFiles: [], pngFiles: [png([12], 'export/Hero A Sprite.png'), png([13], 'export/Hero A,Big Form Sprite.png')], db: base.db });
  assert.deepEqual(only.errors, []);
  assert.deepEqual(only.entries.map(e => [e.id, e.status, !!e.spriteChanged, e.imageChanged]), [['OP9-001', 'changed', true, false], ['OP9-003', 'changed', true, false]]);
  const next = buildPublish(base.db, only);
  const h = next.db.cards.find(c => c.id === 'OP9-001');
  assert.equal(h.image, base.db.cards.find(c => c.id === 'OP9-001').image, 'slika karte ista');
  assert.ok(h.sprite);
  const entry = changelogEntry(base.db, next.db);
  assert.deepEqual(entry.cards.map(c => [c.id, describeChange(c)]), [['OP9-001', 'look: sprite'], ['OP9-003', 'look: sprite']]);
  assert.equal(next.db.version, base.db.version, 'samo sprite: verzija ostaje');
});

test('sprite za kartu koja nije heroj ni Evolution se preskače uz upozorenje', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({ xmlFiles: [], pngFiles: [png([5], 'export/Punch Sprite.png')], db: pub.db });
  assert.match(a.warnings.map(w => w.msg).join('\n'), /sprites are only for heroes and Evolution cards/);
  assert.deepEqual(a.entries, []);
});

test('ponovni uvoz heroja čuva oblik i boju bakugana i sprite', async () => {
  const { pub } = await firstImport();
  const edited = applyAppEdits(pub.db, { 'OP9-001': { bakuganShape: 'dragonoid', bakuganColor: '#ff0000' } }).db;
  const withSprite = buildPublish(edited, await analyzeExport({ xmlFiles: [], pngFiles: [png([12], 'export/Hero A Sprite.png')], db: edited })).db;
  const a = await analyzeExport({ xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...HERO, traits: 'Crew' })), lastModified: 1 }], pngFiles: [png([1], 'export/Hero A.png')], db: withSprite });
  const h = buildPublish(withSprite, a).db.cards.find(c => c.id === 'OP9-001');
  assert.deepEqual([h.bakuganShape, h.bakuganColor, h.traits], ['dragonoid', '#ff0000', ['Crew']]);
  assert.equal(h.sprite, withSprite.cards.find(c => c.id === 'OP9-001').sprite);
});

test('kod na početku imena karte se miče (Card Engine ime = ime PNG-a), Evolution nađe heroja', async () => {
  const hero = { ...HERO, name: 'JO9-001 Giorno', code: 'JO9-001', color: 'Red' };
  const evo = { ...EVO, name: 'JO9-012 Giorno, Requiem', code: 'JO9-012', color: 'Red' };
  const other = { ...ACTION, name: 'OP9-002 Punch', code: 'OP9-099' };
  const parsed = parseCardEngineXml(xml(card(hero), card(evo), card(other)));
  assert.deepEqual(parsed.map(p => [p.code, p.card.name, p.card.hero]), [['JO9-001', 'Giorno', undefined], ['JO9-012', 'Giorno, Requiem', 'Giorno'], ['OP9-099', 'OP9-002 Punch', undefined]]);
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/XMLs/jo.xml', text: xml(card(hero), card(evo)), lastModified: 1 }],
    pngFiles: [png([1], 'export/cards/JO9-001 Giorno.png'), png([2], 'export/cards/JO9-012 Giorno, Requiem.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
});

test('arhiva: objavljeni PNG-ovi (slika karte, sprite) su u data/, token PNG ostaje u arhivi', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/XMLs/x.xml', text: xml(card(HERO), card(TOKEN)), lastModified: 1 }],
    pngFiles: [png([1], 'export/cards/OP9-001 Hero A.png'), png([11], 'export/sprites/OP9-001 Hero A Sprite.png'), png([5], 'export/cards/+2 Damage.png')],
    db: emptyDb(),
  });
  assert.deepEqual([...publishedPngPaths(a)].sort(), ['export/cards/OP9-001 Hero A.png', 'export/sprites/OP9-001 Hero A Sprite.png']);
});

test('izgled (bakugan, sprite) ne diže verziju, skuplja se pod nju i ne broji se kao promjena karte', async () => {
  const { pub } = await firstImport();
  let log = appendChangelog(emptyChangelog(), changelogEntry(emptyDb(), pub.db));
  // oblik i boja bakugana: verzija ostaje 1, karta ne dobije novi rev
  const a = applyAppEdits(pub.db, { 'OP9-001': { bakuganShape: 'dragonoid' } });
  assert.deepEqual([a.db.version, a.bumped, a.db.cards[0].rev], [1, false, pub.db.cards[0].rev]);
  log = appendChangelog(log, changelogEntry(pub.db, a.db));
  const b = applyAppEdits(a.db, { 'OP9-001': { bakuganColor: '#ff0000' } });
  log = appendChangelog(log, changelogEntry(a.db, b.db));
  assert.deepEqual(log.entries.map(e => e.version), [1], 'izgled ide pod v1');
  const hero = log.entries[0].cards.find(c => c.id === 'OP9-001');
  assert.equal(describeChange(hero), 'new · look: bakugan shape, bakugan color');
  // igra (wt) diže verziju; deckovi vide samo igru
  const c = applyAppEdits(b.db, { 'OP9-001': { wt: 3 } });
  assert.deepEqual([c.db.version, c.bumped], [2, true]);
  log = appendChangelog(log, changelogEntry(b.db, c.db));
  const d = applyAppEdits(c.db, { 'OP9-001': { bakuganColor: '#00ff00' } });
  log = appendChangelog(log, changelogEntry(c.db, d.db));
  assert.deepEqual(log.entries.map(e => e.version), [1, 2]);
  assert.equal(describeChange(log.entries[1].cards[0]), 'wt · look: bakugan color');
  assert.deepEqual([...changesSince(log, 1)].map(([id, l]) => [id, l.map(x => x.fields)]), [['OP9-001', [['wt']]]]);
  // stari zapisi: izgled u fields ili sprite: true ne pali deckove
  const old = { entries: [{ version: 3, cards: [{ id: 'X', name: 'X', kind: 'changed', fields: [], image: false, sprite: true }] }, { version: 4, cards: [{ id: 'X', name: 'X', kind: 'changed', fields: ['bakuganShape'], image: false }] }] };
  assert.equal(changesSince(old, 2).size, 0);
  assert.deepEqual(old.entries.map(e => describeChange(e.cards[0])), ['look: sprite', 'look: bakugan shape']);
});

test('uvoz: landscape Evolution s rotiranom verzijom (XML i PNG "(rot)")', async () => {
  const xmlFiles = [{ path: 'export/heroes.xml', text: xml(landCard(LHERO), landCard(LEVO), landCard({ ...LEVO, rot: true })), lastModified: 1 }];
  const pngFiles = [png([1], 'export/OP9-020 Hero B Hero.png'), png([2], 'export/OP9-021 Hero B, Requiem.png'), png([3], 'export/OP9-021 Hero B, Requiem (rot).png')];
  const a = await analyzeExport({ xmlFiles, pngFiles, db: emptyDb() });
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => [e.id, e.status, !!e.rotPng]), [['OP9-020', 'new', false], ['OP9-021', 'new', true]]);
  const pub = buildPublish(emptyDb(), a, new Date('2026-10-24T10:00:00Z'));
  const evo = pub.db.cards.find(c => c.id === 'OP9-021');
  assert.match(evo.image, /^images\/OP9-021\.[0-9a-f]{8}\.png$/);
  assert.match(evo.imageRot, /^images\/OP9-021\.rot\.[0-9a-f]{8}\.png$/);
  assert.equal(pub.writes.length, 3);
  assert.equal(publishedPngPaths(a).size, 3);
  // nova rotirana slika sama: promjena igre (karta u decku), stara rotirana se smije obrisati kad nova ima Steam URL
  const b = await analyzeExport({ xmlFiles: [], pngFiles: [png([9], 'export/OP9-021 Hero B, Requiem (rot).png')], db: pub.db });
  assert.deepEqual(b.entries.map(e => [e.id, e.status, e.rotChanged]), [['OP9-021', 'changed', true]]);
  const pub2 = buildPublish(pub.db, b);
  assert.equal(pub2.bumped, true);
  const evo2 = pub2.db.cards.find(c => c.id === 'OP9-021');
  const oldFile = evo.imageRot.split('/')[1];
  assert.deepEqual(obsoleteImages(pub2.db, [oldFile], { [`OP9-021.rot.${evo2.imageRotHash}`]: 'https://x' }), [oldFile]);
  assert.deepEqual(changelogEntry(pub.db, pub2.db).cards.map(c => [c.id, c.image]), [['OP9-021', true]]);
});

test('normalizeDb: stari tip Character je Hero', () => {
  const db = { version: 3, updated: null, cards: [{ id: 'X-001', type: 'Character' }, { id: 'X-002', type: 'Action' }] };
  assert.deepEqual(normalizeDb(db).cards.map(c => c.type), ['Hero', 'Action']);
  const clean = normalizeDb(db);
  assert.equal(normalizeDb(clean), clean);
});
