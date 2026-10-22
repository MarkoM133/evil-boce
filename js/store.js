// Izvor podataka za app: Drive folder (File System Access, računalo) ili lokalni server (mobitel preko Tailscalea).
// Oba imaju isto sučelje za bazu karata, slike i deckove; uvoz i Objava postoje samo u folderu.
import { emptyDb, thumbName } from './importer.js';
import * as fs from './fsdir.js';

export class ConflictError extends Error {
  constructor(current) {
    super('Deck je u međuvremenu promijenjen na drugom uređaju.');
    this.current = current;
  }
}

function summary(slug, d) {
  return {
    slug,
    name: d.name,
    heroes: d.heroes ?? [],
    count: Object.values(d.cards ?? {}).reduce((s, n) => s + n, 0),
    rev: d.rev ?? 0,
    updated: d.updated ?? null,
  };
}

const LOGO_FILES = ['logo.png', 'logo.jpg', 'logo.jpeg', 'logo.webp'];

// ---------- server ----------

export async function probeServer() {
  try {
    const r = await fetch('api/info', { cache: 'no-store' });
    if (!r.ok) return null;
    const info = await r.json();
    return typeof info.version === 'number' ? info : null;
  } catch {
    return null;
  }
}

async function json(r) {
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || `Server je vratio ${r.status}`);
  return body;
}

export function serverStore(info) {
  return {
    kind: 'server',
    name: info.folder,
    canImport: false,
    async readDb() {
      const r = await fetch('data/cards.json', { cache: 'no-store' });
      if (r.status === 404) return emptyDb();
      return json(r);
    },
    // thumb: URL sličice; ako je nema na serveru, pozivatelj padne na punu sliku (onerror).
    async imageUrl(card, { thumb = false } = {}) {
      if (!card.image) return null;
      return thumb ? `data/thumbs/${thumbName(card)}` : `data/${card.image}`;
    },
    async logoUrl() {
      return info.logo ? 'logo' : null;
    },
    async listDecks() {
      return json(await fetch('api/decks', { cache: 'no-store' }));
    },
    async readDeck(slug) {
      return json(await fetch(`api/decks/${slug}`, { cache: 'no-store' }));
    },
    async saveDeck(slug, deck, baseRev) {
      const r = await fetch(`api/decks/${slug}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'If-Match': String(baseRev) },
        body: JSON.stringify(deck),
      });
      if (r.status === 409) throw new ConflictError((await r.json()).current);
      return json(r);
    },
    async deleteDeck(slug, baseRev) {
      const r = await fetch(`api/decks/${slug}`, { method: 'DELETE', headers: { 'If-Match': String(baseRev) } });
      if (r.status === 409) throw new ConflictError((await r.json()).current);
      return json(r);
    },
  };
}

// ---------- Drive folder ----------

export function folderStore(root) {
  const urls = new Map();
  const readJson = async p => {
    const t = await fs.readText(root, p);
    return t ? JSON.parse(t) : null;
  };
  return {
    kind: 'folder',
    name: root.name,
    canImport: true,
    root,
    async readDb() {
      return (await readJson('data/cards.json')) ?? emptyDb();
    },
    // thumb: sličica ako postoji, inače null (pozivatelj uzme punu sliku).
    async imageUrl(card, { thumb = false } = {}) {
      if (!card.image) return null;
      const path = thumb ? `data/thumbs/${thumbName(card)}` : `data/${card.image}`;
      if (!urls.has(path)) {
        const f = await fs.getFile(root, path);
        urls.set(path, f ? URL.createObjectURL(f) : null);
      }
      return urls.get(path);
    },
    dropImageUrls() {
      for (const u of urls.values()) if (u) URL.revokeObjectURL(u);
      urls.clear();
    },
    async logoUrl() {
      for (const name of LOGO_FILES) {
        const f = await fs.getFile(root, name);
        if (f) return URL.createObjectURL(f);
      }
      return null;
    },
    async listDecks() {
      const out = [];
      for (const n of await fs.listFileNames(root, 'decks')) {
        if (!n.endsWith('.json')) continue;
        const slug = n.slice(0, -5);
        try {
          out.push(summary(slug, await readJson(`decks/${n}`)));
        } catch {
          out.push({ slug, name: slug, broken: true });
        }
      }
      return out.sort((a, b) => String(b.updated).localeCompare(String(a.updated)));
    },
    async readDeck(slug) {
      const d = await readJson(`decks/${slug}.json`);
      if (!d) throw new Error('Nema tog decka.');
      return { slug, ...d };
    },
    async saveDeck(slug, deck, baseRev) {
      const current = await readJson(`decks/${slug}.json`);
      if ((current?.rev ?? 0) !== baseRev) throw new ConflictError(current && { slug, ...current });
      const next = {
        name: deck.name.trim(),
        heroes: deck.heroes,
        cards: Object.fromEntries(Object.entries(deck.cards).filter(([, n]) => n > 0)),
        catalogVersion: deck.catalogVersion ?? 0,
        rev: (current?.rev ?? 0) + 1,
        updated: new Date().toISOString(),
      };
      await fs.writeFile(root, `decks/${slug}.json`, JSON.stringify(next, null, 2) + '\n');
      return { slug, ...next };
    },
    async deleteDeck(slug, baseRev) {
      const current = await readJson(`decks/${slug}.json`);
      if (current && (current.rev ?? 0) !== baseRev) throw new ConflictError({ slug, ...current });
      await fs.removeFile(root, `decks/${slug}.json`);
      return { ok: true };
    },
  };
}
