// Which file of the repo a GET may have (the web app's own files; the shared folder's have their own routes).
// The rule is checked on the path as the disk resolves it, never on the URL's text: "/js/..%2Fserver/x" and
// "/server%5Cx" both walked round a check of the first URL segment and got server/config.local.json, which holds
// the API key (code review 2026-11-13).
import fs from 'node:fs/promises';
import path from 'node:path';

// For everyone the server answers: the web app and nothing else.
const PUBLIC = ['index.html', 'css', 'js'];
// Never, not even for this computer: the server's own folder (config.local.json), git, packages.
const NEVER = ['server', '.git', 'node_modules'];

// The file under `base` that `rel` names, or null when it leaves `base`.
export function inside(base, rel) {
  const file = path.resolve(base, '.' + path.sep + rel);
  return file === base || file.startsWith(base + path.sep) ? file : null;
}

// {file} to send, or {status} to refuse with. `local`: the request comes from this computer, which may also read
// the rest of the repo (docs/ with the mockups and the test page), dot files and the NEVER folders excepted.
export async function repoFile(root, rel, local) {
  const asked = inside(root, rel.endsWith('/') ? rel + 'index.html' : rel);
  if (!asked) return { status: 403 };
  let file, base;
  try {
    // The real path: a link, a short name (SERVER~1), another case or a trailing dot all end up as what they are.
    [file, base] = await Promise.all([fs.realpath(asked), fs.realpath(root)]);
  } catch {
    return { status: 404 };
  }
  if (!file.startsWith(base + path.sep)) return { status: 403 };
  const parts = path.relative(base, file).split(path.sep).map(s => s.toLowerCase());
  if (parts.some(s => s.startsWith('.')) || NEVER.includes(parts[0])) return { status: 404 };
  if (!local && !PUBLIC.includes(parts[0])) return { status: 404 };
  return { file };
}
