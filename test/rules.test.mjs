import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRules, rulesHtml, searchRules, markWord } from '../js/rules.js';

const MD = `# Evil Boće – Rules

> DRAFT for checking.

## 1. The game in short

You **win** with 3 stages.

## 8. Battle

**Who wins:** the higher PWR. **[?]**

| Stat | Meaning |
|---|---|
| **HP** | Hit points. |
| **KB** | How far it is knocked. |

- One
  and more of one
- Two
`;

test('pravila: uvod pa po jedan odjeljak za svaki ##, naslov # se ne prikazuje', () => {
  const s = parseRules(MD);
  assert.deepEqual(s.map(x => [x.id, x.title]), [['intro', ''], ['1-the-game-in-short', '1. The game in short'], ['8-battle', '8. Battle']]);
  assert.match(s[0].html, /class="rl-note">DRAFT for checking/);
  assert.doesNotMatch(s[0].html, /Evil Boće – Rules/);
  assert.equal(s[1].html, '<p>You <strong>win</strong> with 3 stages.</p>');
});

test('pravila: tablica bez retka zaglavlja, lista s nastavkom retka, oznaka [?]', () => {
  const html = parseRules(MD)[2].html;
  assert.match(html, /<tr><th><strong>HP<\/strong><\/th><td>Hit points\.<\/td><\/tr>/);
  assert.doesNotMatch(html, /Meaning/);
  assert.match(html, /<li>One and more of one<\/li><li>Two<\/li>/);
  assert.match(html, /class="rl-q"/);
  assert.equal(rulesHtml(['a < b & c']), '<p>a &lt; b &amp; c</p>');
});

test('pravila: traženje ostavi odjeljke s riječju, a riječ se označi samo u tekstu', () => {
  const s = parseRules(MD).slice(1);
  assert.deepEqual(searchRules(s, 'KNOCKED').map(x => x.id), ['8-battle']);
  assert.equal(searchRules(s, '  ').length, 2);
  assert.equal(searchRules(s, 'stun').length, 0);
  assert.equal(markWord('<p class="rl-note">note</p>', 'note'), '<p class="rl-note"><mark>note</mark></p>');
  assert.equal(markWord('<p>a+b</p>', 'a+b'), '<p><mark>a+b</mark></p>');
});

// --- code review 2026-11-13 ---

test('pravila: red s # koji nije poznat naslov ne zaustavlja stranicu, nego je podnaslov', () => {
  for (const line of ['#### Deeper', '###NoSpace', '#1 rule', '##', '#']) {
    const html = rulesHtml(['Before.', '', line, '', 'After.']);
    assert.match(html, /<p>Before\.<\/p>/, line);
    assert.match(html, /<p>After\.<\/p>/, line);
    assert.match(html, /<h4>/, line);
  }
  assert.match(rulesHtml(['#### Deeper']), /<h4>Deeper<\/h4>/);
  // And through the whole parse, as the page does it.
  assert.equal(parseRules('## A\n\ntext\n\n#### deeper\n\nmore').length, 2);
});

test('pravila: numerirana lista koju prekine odlomak broji dalje', () => {
  const html = rulesHtml(['1. One', '2. Two', '', 'A paragraph between.', '', '4. **Starting hand:** five cards', '5. Five']);
  assert.match(html, /<ol start="1"><li>One<\/li><li>Two<\/li><\/ol>/);
  assert.match(html, /<ol start="4"><li><strong>Starting hand:<\/strong> five cards<\/li><li>Five<\/li><\/ol>/);
});

test('pravila: oznaka traženog ne dira entitete ni tagove', () => {
  const html = rulesHtml(['Rock & roll <fast> and **bold** amp.']);
  assert.equal(markWord(html, 'a').includes('&<mark>a</mark>mp;'), false);
  assert.match(markWord(html, 'amp'), /&amp; roll .* <mark>amp<\/mark>\./);
  assert.match(markWord(html, '&'), /Rock <mark>&amp;<\/mark> roll/);
  assert.match(markWord(html, '>'), /^<p>Rock/);
  assert.match(markWord(html, '<fast>'), /<mark>&lt;fast&gt;<\/mark>/);
  assert.match(markWord(html, 'bold'), /<strong><mark>bold<\/mark><\/strong>/);
});

test('pravila: traženje čita tekst bez Markdown oznaka', () => {
  const s = parseRules(MD);
  assert.deepEqual(searchRules(s.slice(1), 'win with').map(x => x.id), ['1-the-game-in-short']);
});
