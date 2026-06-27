import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const cfgText = fs.readFileSync(path.join(projectRoot, 'supabase-config.js'), 'utf8');
const url = cfgText.match(/url:\s*'([^']+)'/)[1];
const anonKey = cfgText.match(/anonKey:\s*'([^']+)'/)[1];
const h = { apikey: anonKey, Authorization: 'Bearer ' + anonKey };

const base = process.argv[2];
if (!base) throw new Error('usage: node upload-webp.mjs <webpDir>');

function walk(dir, root, out) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) walk(full, root, out);
    else out.push(path.relative(root, full).split(path.sep).join('/'));
  }
}

const files = [];
walk(base, base, files);
console.log('files to upload:', files.length);

for (const rel of files) {
  const buf = fs.readFileSync(path.join(base, rel));
  const res = await fetch(`${url}/storage/v1/object/center-images/${rel}`, {
    method: 'POST',
    headers: { ...h, 'content-type': 'image/webp', 'x-upsert': 'true', 'cache-control': '3600' },
    body: buf,
  });
  console.log(rel, res.status, buf.length);
  if (!res.ok) console.log('  ERROR:', await res.text());
}
