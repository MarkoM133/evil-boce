// Podaci za TTS Sync na izmišljenoj bazi.
import test from 'node:test';
import assert from 'node:assert/strict';
import { ttsDescription, ttsPayload, mergeSteamUrls, CARD_BACK_URL } from '../js/tts.js';

const HERO = { id: 'OP9-001', name: 'Hero A', type: 'Character', color: 'Cyan', stats: { hp: 8, dmg: 3, pwr: 3000, rng: 4, kb: 3 }, traits: ['Crew', 'Fruit'], text: '[Range] Postroll: heal.', wt: 3, image: 'images/OP9-001.aaaaaaaa.png', imageHash: 'aaaaaaaa', rev: 2, bakuganShape: 'dragonoid', bakuganColor: '#ff0000', sprite: 'sprites/OP9-001.cccccccc.png', spriteHash: 'cccccccc' };
const ACTION = { id: 'OP9-002', name: 'Punch', type: 'Action', color: 'Cyan', cost: 1, bonus: { pwr: 2000, dmg: -1 }, traits: ['Hero A'], text: 'Battle Phase:', image: 'images/OP9-002.bbbbbbbb.png', imageHash: 'bbbbbbbb', rev: 1 };
const KICK = { id: 'OP9-003', name: 'Kick', type: 'Action', color: 'Cyan', cost: 2, bonus: {}, values: { rng: 3, kb: 3 }, traits: ['Hero A'], text: 'x', image: 'images/OP9-003.dddddddd.png', imageHash: 'dddddddd', rev: 1 };
const EVO = { id: 'OP9-004', name: 'Hero A, Big Form', type: 'Evolution', color: 'Cyan', cost: 2, evo: 1, hero: 'Hero A', stats: { hp: 10, dmg: 3, pwr: 4000, rng: 4, kb: 3 }, traits: [], text: 'y', image: 'images/OP9-004.eeeeeeee.png', imageHash: 'eeeeeeee', rev: 1 };
const STAGE = { id: 'Stage-009', name: 'Island', type: 'Stage', color: null, traits: [], text: 'When revealed.', image: 'images/Stage-009.ffffffff.png', imageHash: 'ffffffff', rev: 1 };

test('opis karte u obliku iz savea (zaglavlje, statsi/bonusi, traitovi, tekst)', () => {
  assert.equal(ttsDescription(HERO), 'Character  ·  OP9-001\nHP 8  DMG 3  Power 3000  Range 4  Knockback 3\nCrew/Fruit\n\n[Range] Postroll: heal.');
  assert.equal(ttsDescription(ACTION), 'Action  ·  Cost 1  ·  OP9-002\nDMG -1  Power +2000\nHero A\n\nBattle Phase:');
  assert.equal(ttsDescription(KICK), 'Action  ·  Cost 2  ·  OP9-003\nRange 3  Knockback 3\nHero A\n\nx');
  assert.equal(ttsDescription(EVO), 'Evolution  ·  Cost 2  ·  Evo 1  ·  OP9-004\nHP 10  DMG 3  Power 4000  Range 4  Knockback 3\n\ny');
  assert.equal(ttsDescription(STAGE), 'Stage  ·  Stage-009\n\nWhen revealed.');
});

test('payload: lokalne putanje dok nema Steam URL-a, heroji sa statsima i bakuganom', () => {
  const db = { version: 3, cards: [STAGE, EVO, ACTION, HERO, KICK] };
  const opts = { drivePath: String.raw`C:\Users\x\EvilBoce`, steam: { 'OP9-002.bbbbbbbb': 'https://steamusercontent-a.akamaihd.net/ugc/1/A/' }, bakugani: [{ id: 'dragonoid', name: 'Dragonoid', meshUrl: 'https://steamusercontent-a.akamaihd.net/ugc/2/M/' }] };
  const p = ttsPayload(db, opts);
  assert.equal(p.back, CARD_BACK_URL);
  assert.deepEqual(p.cards.map(c => [c.id, c.deck]), [['OP9-001', 1000], ['OP9-002', 1001], ['OP9-003', 1002], ['OP9-004', 1003], ['Stage-009', 1004]]);
  const hero = p.cards[0];
  assert.equal(hero.face, 'file:///C:/Users/x/EvilBoce/data/images/OP9-001.aaaaaaaa.png');
  assert.equal(hero.key, 'OP9-001.aaaaaaaa');
  assert.equal(p.cards[1].face, 'https://steamusercontent-a.akamaihd.net/ugc/1/A/', 'Steam URL ima prednost');
  assert.equal(p.cards[3].nickname, 'Hero A, Big Form');
  assert.deepEqual(p.heroes, [{
    id: 'OP9-001', name: 'Hero A',
    stats: { max: 8, dmg: 3, pwr: 3, rng: 4, kb: 3, wt: 3 },
    bakugan: { shape: 'dragonoid', name: 'Dragonoid', mesh: 'https://steamusercontent-a.akamaihd.net/ugc/2/M/', texture: 'file:///C:/Users/x/EvilBoce/data/bakugani/boje/dragonoid-ff0000-ff0000.jpg', textureKey: 'bakugan:dragonoid-ff0000-ff0000', color: [1, 1, 1] },
    sprite: 'file:///C:/Users/x/EvilBoce/data/sprites/OP9-001.cccccccc.png', spriteKey: 'sprite:OP9-001.cccccccc',
  }]);
});

test('Steam URL-ovi iz TTS-a: samo poznati ključevi i Steam adrese', () => {
  const { steam, added } = mergeSteamUrls({ 'OP9-001.aaaaaaaa': 'https://steamusercontent-a.akamaihd.net/ugc/1/A/' }, {
    'OP9-001.aaaaaaaa': 'https://steamusercontent-a.akamaihd.net/ugc/1/A/',
    'OP9-002.bbbbbbbb': 'https://steamusercontent-a.akamaihd.net/ugc/3/B/',
    'sprite:OP9-001.cccccccc': 'https://steamusercontent-a.akamaihd.net/ugc/4/C/',
    'bakugan:dragonoid': 'https://steamusercontent-a.akamaihd.net/ugc/5/D/',
    'OP9-003.dddddddd': 'file:///C:/x.png',
    'evil': 'https://steamusercontent-a.akamaihd.net/ugc/6/E/',
  });
  assert.equal(added, 3);
  assert.deepEqual(Object.keys(steam).sort(), ['OP9-001.aaaaaaaa', 'OP9-002.bbbbbbbb', 'bakugan:dragonoid', 'sprite:OP9-001.cccccccc']);
});
