// File System Access API: odabrani Drive folder "Evil Boce/" i putanje unutar njega.

const DB_NAME = 'evil-boce';
const STORE = 'handles';

function idb(mode, fn) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(DB_NAME, 1);
    open.onupgradeneeded = () => open.result.createObjectStore(STORE);
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const tx = open.result.transaction(STORE, mode);
      const req = fn(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
    };
  });
}

export const saveRoot = handle => idb('readwrite', s => s.put(handle, 'root'));
export const loadRoot = () => idb('readonly', s => s.get('root')).catch(() => undefined);

export async function pickRoot() {
  const handle = await window.showDirectoryPicker({ id: 'evil-boce', mode: 'readwrite' });
  await saveRoot(handle);
  return handle;
}

// 'granted' | 'prompt' | 'denied'. request=true smije se zvati samo iz klika.
export async function permission(handle, request = false) {
  const opts = { mode: 'readwrite' };
  let state = await handle.queryPermission(opts);
  if (state !== 'granted' && request) state = await handle.requestPermission(opts);
  return state;
}

async function dirAt(root, parts, create) {
  let d = root;
  for (const p of parts) {
    try {
      d = await d.getDirectoryHandle(p, { create });
    } catch (e) {
      if (e.name === 'NotFoundError') return null;
      throw e;
    }
  }
  return d;
}

function split(path) {
  const parts = path.split('/').filter(Boolean);
  return { dirs: parts.slice(0, -1), name: parts[parts.length - 1] };
}

export async function getDir(root, path, create = false) {
  return dirAt(root, path.split('/').filter(Boolean), create);
}

export async function getFile(root, path) {
  const { dirs, name } = split(path);
  const d = await dirAt(root, dirs, false);
  if (!d) return null;
  try {
    return await (await d.getFileHandle(name)).getFile();
  } catch (e) {
    if (e.name === 'NotFoundError') return null;
    throw e;
  }
}

export async function readText(root, path) {
  const f = await getFile(root, path);
  return f ? f.text() : null;
}

export async function writeFile(root, path, data) {
  const { dirs, name } = split(path);
  const d = await dirAt(root, dirs, true);
  const w = await (await d.getFileHandle(name, { create: true })).createWritable();
  await w.write(data);
  await w.close();
}

export async function removeFile(root, path) {
  const { dirs, name } = split(path);
  const d = await dirAt(root, dirs, false);
  if (d) await d.removeEntry(name);
}

export async function listFileNames(root, path) {
  const d = await getDir(root, path);
  if (!d) return [];
  const out = [];
  for await (const [name, h] of d.entries()) if (h.kind === 'file') out.push(name);
  return out;
}

// Svi fileovi ispod foldera, rekurzivno: [{ path, file }]. skip(path) preskače podfolder.
export async function walkFiles(dir, prefix, skip = () => false) {
  const out = [];
  for await (const [name, h] of dir.entries()) {
    const path = `${prefix}/${name}`;
    if (h.kind === 'directory') {
      if (!skip(path)) out.push(...(await walkFiles(h, path, skip)));
    } else out.push({ path, file: await h.getFile() });
  }
  return out;
}

// Premjesti file. Pravo premještanje (handle.move) gdje ga preglednik zna: sinkronizaciji je to preimenovanje,
// ne novi file. Inače kopija + brisanje (datum izmjene nije bitan, file ide u arhivu).
export async function moveFile(root, from, to) {
  const a = split(from);
  const b = split(to);
  const src = await dirAt(root, a.dirs, false);
  if (!src) return;
  let handle;
  try {
    handle = await src.getFileHandle(a.name);
  } catch (e) {
    if (e.name === 'NotFoundError') return;
    throw e;
  }
  const dst = await dirAt(root, b.dirs, true);
  if (typeof handle.move === 'function') {
    try {
      await handle.move(dst, b.name);
      return;
    } catch {
      // npr. stariji preglednik ili drugi disk: dolje kopija + brisanje
    }
  }
  await writeFile(root, to, await handle.getFile());
  await src.removeEntry(a.name);
}

// Obriše folder ako je prazan; inače ga ostavi.
export async function removeDirIfEmpty(root, path) {
  const { dirs, name } = split(path);
  const d = await dirAt(root, dirs, false);
  if (!d) return;
  try {
    await d.removeEntry(name);
  } catch (e) {
    if (e.name !== 'InvalidModificationError' && e.name !== 'NotFoundError') throw e;
  }
}
