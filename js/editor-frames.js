// Card editor › Frames: predlošci karata (data/card-frames/<ime>/layout.json) sa živim previewom.
// Kućice se mogu uređivati (JSON) i vidjeti obrubljene preko karte; sprema samo Marko (dogovor, ne zaštita).
import * as fs from './fsdir.js';
import { loadTemplate, renderCard, loadImage, templateName } from './render.js';

export const TEMPLATES = ['action', 'hero', 'evolution', 'stage', 'core'];

// Kućice iz layouta za obrub: [{ name, box: [x, y, w, h] }].
export function layoutBoxes(L) {
  const out = [];
  const add = (name, b) => { if (Array.isArray(b) && b.length >= 4 && b.slice(0, 4).every(Number.isFinite)) out.push({ name, box: b.slice(0, 4) }); };
  for (const [k, v] of Object.entries(L ?? {})) {
    if (['size', 'layers', 'frames', 'icons', 'bg', 'statTints', 'about', 'name', 'kind', 'frame', 'interim', 'plateColor'].includes(k)) continue;
    if (Array.isArray(v)) add(k, v);
    else if (v && typeof v === 'object') {
      if (v.box) add(k, v.box);
      for (const [k2, v2] of Object.entries(v)) {
        if (v2 && typeof v2 === 'object' && !Array.isArray(v2)) for (const [k3, v3] of Object.entries(v2)) add(`${k}.${k2}.${k3}`, v3);
        else if (k2 !== 'box') add(`${k}.${k2}`, v2);
      }
    }
  }
  return out;
}

// ctx: { h, state, store, canWrite, who, render, guard, toast, drafts(), onSaved(name) }
export function createFramesView(ctx) {
  const { h } = ctx;
  const v = { name: 'action', tpl: null, tplFor: null, text: '', error: null, sample: null, outline: true, canvas: null, art: null, artFor: null };

  async function loadTpl() {
    v.tplFor = v.name;
    v.tpl = await loadTemplate(v.name, rel => ctx.store().dataUrl(rel)).catch(e => { v.error = e.message; return null; });
    v.text = v.tpl ? JSON.stringify(v.tpl.layout, null, 2) : '';
    v.error = v.tpl ? null : v.error;
    ctx.render();
  }

  const samples = () => ctx.state.db.cards.filter(c => !c.deleted && templateName({ ...c, ...(ctx.drafts()?.cards?.[c.id] ?? {}) }) === v.name);

  async function draw() {
    if (!v.canvas || !v.tpl) return;
    let layout;
    try {
      layout = JSON.parse(v.text);
      v.error = null;
    } catch (e) {
      v.error = `Not valid JSON: ${e.message}`;
      document.getElementById('ce-frames-error')?.replaceChildren(v.error);
      return;
    }
    document.getElementById('ce-frames-error')?.replaceChildren();
    const base = samples().find(c => c.id === v.sample) ?? samples()[0];
    if (!base) return;
    const card = { ...base, ...(ctx.drafts()?.cards?.[base.id] ?? {}) };
    if (v.artFor !== card.art) {
      v.artFor = card.art;
      const u = card.art ? await ctx.store().dataUrl(card.art) : null;
      v.art = u ? await loadImage(u).catch(() => null) : null;
      const e = card.emblem ? await ctx.store().dataUrl(card.emblem) : null;
      v.emblem = e ? await loadImage(e).catch(() => null) : null;
    }
    renderCard(v.canvas, card, { ...v.tpl, layout }, v.art, v.emblem);
    if (!v.outline) return;
    const g = v.canvas.getContext('2d');
    g.save();
    g.lineWidth = 4;
    g.font = 'bold 26px sans-serif';
    layoutBoxes(layout).forEach(({ name, box: [x, y, w, bh] }, i) => {
      const hue = (i * 47) % 360;
      g.strokeStyle = `hsl(${hue} 90% 55%)`;
      g.fillStyle = `hsl(${hue} 90% 55%)`;
      g.strokeRect(x, y, w, bh);
      g.fillText(name, x + 6, y + 28);
    });
    g.restore();
  }

  async function save() {
    const layout = JSON.parse(v.text);
    await fs.writeFile(ctx.store().root, `data/card-frames/${v.name}/layout.json`, JSON.stringify(layout, null, 2) + '\n');
    ctx.onSaved(v.name);
    ctx.toast(`Frame ${v.name} saved. The editor and the next Publish use it.`);
    await loadTpl();
  }

  function render() {
    if (v.tplFor !== v.name) {
      loadTpl();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the frame…'));
    }
    const marko = ctx.who() === 'Marko';
    const L = v.tpl?.layout;
    const layerRows = L?.kind === 'hero' ? Object.entries(v.tpl.frames ?? {}).map(([k, img]) => [`${L.frame.replace('{letter}', k)}`, !!img])
      : (L?.layers ?? []).filter(l => !l.art).map(l => [l.src + (l.tint ? ` (tint ${l.tint === true ? 'card colour' : l.tint})` : ''), !!v.tpl.layers]);
    const list = samples();
    v.sample = list.some(c => c.id === v.sample) ? v.sample : list[0]?.id ?? null;
    v.canvas = h('canvas', { class: `ce-canvas${['hero', 'evolution'].includes(v.name) ? ' wide' : ''}` });
    const area = h('textarea', { class: 'ce-frames-json', rows: 30, spellcheck: false, value: v.text, oninput: e => { v.text = e.target.value; draw(); } });
    setTimeout(draw, 0);
    return h('div', { class: 'card-editor ce-frames' },
      h('aside', { class: 'ce-list' }, h('ul', {}, TEMPLATES.map(n => h('li', {}, h('button', { class: `ce-item${n === v.name ? ' active' : ''}`, type: 'button', onclick: () => { v.name = n; v.tplFor = null; ctx.render(); } }, n))))),
      h('section', { class: 'ce-form' },
        h('div', { class: 'ce-title' }, h('h2', {}, `Frame: ${v.name}`)),
        v.error && !v.tpl ? h('p', { class: 'warn' }, v.error) : null,
        h('p', { class: 'muted small' }, L?.about ?? ''),
        layerRows.length ? h('ul', { class: 'small' }, layerRows.map(([n, ok]) => h('li', { class: ok ? '' : 'warn' }, `${ok ? '✓' : '✕ missing'} ${n}`))) : null,
        h('label', { class: 'ce-field' }, h('span', {}, 'layout.json (boxes are [x, y, w, h] in card pixels)'), area),
        h('p', { id: 'ce-frames-error', class: 'warn small' }),
        h('div', { class: 'ce-actions' },
          h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite() || !marko, onclick: () => ctx.guard(save) }, 'Save frame'),
          h('button', { class: 'ghost', type: 'button', onclick: () => { v.text = JSON.stringify(L, null, 2); ctx.render(); } }, 'Revert'),
          !ctx.canWrite() ? h('small', { class: 'muted' }, 'Saving needs the shared folder.') : !marko ? h('small', { class: 'muted' }, 'Only Marko changes the frames.') : null)),
      h('section', { class: 'ce-preview' },
        h('div', { class: 'ce-row' },
          h('select', { 'aria-label': 'Sample card', onchange: e => { v.sample = e.target.value; draw(); } }, list.map(c => h('option', { value: c.id, selected: c.id === v.sample }, `${c.id} ${c.name}`))),
          h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: v.outline, onchange: e => { v.outline = e.target.checked; draw(); } }), 'Outline the boxes')),
        v.canvas));
  }

  return { render };
}
