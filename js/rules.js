// Rules (Marko 2026-11-11, W1 with search): the players' rules from data/rules/rules.md in the shared folder, the
// same file the game shows under RULES in its pause menu. Card Studio as a companion beside a match: contents on
// the left, the whole text on the right, and a search that keeps only the sections with the word, marked.
// The rules are not public: they come with the data, like the cards, never from the repo.

export const RULES_PATH = 'data/rules/rules.md';

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// One line of Markdown: **bold**, `code`, *italic*, and **[?]** (a wording still to be checked).
function inline(s) {
  return esc(s)
    .replace(/\*\*\[\?\]\*\*/g, '<span class="rl-q" title="Wording still to be checked">?</span>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/`(.+?)`/g, '<code>$1</code>')
    .replace(/(^|[^*\w])\*(?!\s)([^*]+?)\*/g, '$1<em>$2</em>');
}

// The rules as sections: text before the first "## " is the intro (its "# " title dropped), then one per "## ".
// Each has an id for the contents, its title, its plain text (for the search) and its HTML.
export function parseRules(md) {
  const out = [];
  let cur = { id: 'intro', title: '', lines: [] };
  for (const line of md.replace(/\r\n/g, '\n').split('\n')) {
    if (line.startsWith('## ')) {
      out.push(cur);
      const title = line.slice(3).trim();
      cur = { id: title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''), title, lines: [] };
    } else if (!line.startsWith('# ')) cur.lines.push(line);
  }
  out.push(cur);
  return out.map(s => ({ id: s.id, title: s.title, text: s.lines.join('\n'), html: rulesHtml(s.lines) }));
}

// Markdown lines to HTML: paragraphs, "- " and "1. " lists (an indented line goes on with its item), "| … |"
// tables (the first column as a heading), "> " notes and "### " subheadings.
export function rulesHtml(lines) {
  const html = [];
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    if (l.startsWith('### ')) { html.push(`<h4>${inline(l.slice(4))}</h4>`); i++; continue; }
    if (l.startsWith('> ')) { html.push(`<p class="rl-note">${inline(l.slice(2))}</p>`); i++; continue; }
    if (l.startsWith('|')) {
      const rows = [];
      while (i < lines.length && lines[i].startsWith('|')) rows.push(lines[i++]);
      const cells = r => r.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
      const body = rows.filter(r => !/^\|[\s|:-]+\|$/.test(r.trim())).slice(1)
        .map(r => `<tr>${cells(r).map((c, k) => (k === 0 ? `<th>${inline(c)}</th>` : `<td>${inline(c)}</td>`)).join('')}</tr>`).join('');
      html.push(`<div class="rl-table"><table>${body}</table></div>`);
      continue;
    }
    if (/^(- |\d+\. )/.test(l)) {
      const ordered = /^\d+\. /.test(l);
      const items = [];
      while (i < lines.length && lines[i].trim() && /^(- |\d+\. | {2})/.test(lines[i])) {
        if (/^ {2}/.test(lines[i])) items[items.length - 1] += ' ' + lines[i].trim();
        else items.push(lines[i].replace(/^(- |\d+\. )/, ''));
        i++;
      }
      const tag = ordered ? 'ol' : 'ul';
      html.push(`<${tag}>${items.map(t => `<li>${inline(t)}</li>`).join('')}</${tag}>`);
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|> |\||- |\d+\. )/.test(lines[i])) para.push(lines[i++]);
    html.push(`<p>${inline(para.join(' '))}</p>`);
  }
  return html.join('');
}

// Sections that have the word (in the title or the text), case not minded; all of them for an empty search.
export function searchRules(sections, query) {
  const q = query.trim().toLowerCase();
  if (!q) return sections;
  return sections.filter(s => s.title.toLowerCase().includes(q) || s.text.toLowerCase().includes(q));
}

// The word marked in HTML, only in text, never inside a tag.
export function markWord(html, query) {
  const q = query.trim();
  if (!q) return html;
  const re = new RegExp(`(${q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})(?![^<]*>)`, 'gi');
  return html.replace(re, '<mark>$1</mark>');
}

export function renderRules({ h, state }) {
  const page = h('div', { class: 'rl' }, h('p', { class: 'muted' }, 'Loading the rules…'));
  (async () => {
    if (state.rulesMd == null) state.rulesMd = (await state.store.readRules().catch(() => null)) ?? '';
    page.replaceChildren(h('div', { class: 'rl-head' }, h('h2', {}, 'Rules')));
    if (!state.rulesMd.trim()) {
      page.append(h('p', { class: 'muted' }, `No rules in the shared folder yet (${RULES_PATH}).`));
      return;
    }
    const all = parseRules(state.rulesMd);
    const intro = all[0];
    const parts = all.slice(1);
    const toc = h('nav', { class: 'rl-toc', 'aria-label': 'Contents' });
    const text = h('article', { class: 'rl-text' });
    const none = h('p', { class: 'muted', hidden: true });
    const draw = () => {
      const q = state.rulesQ ?? '';
      const shown = searchRules(parts, q);
      toc.replaceChildren(...shown.map(s => h('a', { href: `#rl-${s.id}`, onclick: e => {
        e.preventDefault();
        document.getElementById(`rl-${s.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
        toc.querySelectorAll('a').forEach(a => a.classList.toggle('on', a === e.currentTarget));
      } }, s.title)));
      text.innerHTML = (q.trim() ? '' : intro.html) + shown.map(s => `<section id="rl-${s.id}"><h3>${esc(s.title)}</h3>${markWord(s.html, q)}</section>`).join('');
      none.hidden = shown.length > 0;
      none.textContent = `Nothing in the rules about “${q.trim()}”.`;
    };
    const search = h('input', { type: 'search', class: 'rl-search', placeholder: 'Search the rules: stun, ring-out, combo…', value: state.rulesQ ?? '',
      'aria-label': 'Search the rules', oninput: e => { state.rulesQ = e.target.value; draw(); } });
    page.append(search, h('div', { class: 'rl-book' }, toc, h('div', { class: 'rl-main' }, none, text)));
    draw();
  })();
  return page;
}
