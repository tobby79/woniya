import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const cfgText = fs.readFileSync(path.join(projectRoot, 'supabase-config.js'), 'utf8');
const url = cfgText.match(/url:\s*'([^']+)'/)[1];
const anonKey = cfgText.match(/anonKey:\s*'([^']+)'/)[1];
const h = (extra = {}) => ({ apikey: anonKey, Authorization: 'Bearer ' + anonKey, ...extra });

async function req(endpoint, options = {}) {
  const res = await fetch(`${url}${endpoint}`, { ...options, headers: h(options.headers) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${options.method || 'GET'} ${endpoint} failed (${res.status}): ${text}`);
  return text ? JSON.parse(text) : null;
}

function toWebp(p) {
  return p && p.toLowerCase().endsWith('.jpg') ? p.slice(0, -4) + '.webp' : p;
}

// 1) center_media.photo_url
const media = await req('/rest/v1/center_media?select=id,photo_url');
let mediaUpdated = 0;
for (const row of media) {
  const next = toWebp(row.photo_url);
  if (next === row.photo_url) continue;
  await req(`/rest/v1/center_media?id=eq.${row.id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ photo_url: next }),
  });
  mediaUpdated++;
}
console.log(`center_media: ${mediaUpdated}/${media.length} rows updated to .webp`);

// 2) centers.card_image + centers.director.photo
const centers = await req('/rest/v1/centers?select=id,slug,card_image,director');
let centersUpdated = 0;
for (const c of centers) {
  const nextCard = toWebp(c.card_image);
  const nextDirector = c.director ? { ...c.director, photo: toWebp(c.director.photo) } : c.director;
  const changed = nextCard !== c.card_image || (c.director && nextDirector.photo !== c.director.photo);
  if (!changed) continue;
  await req(`/rest/v1/centers?id=eq.${c.id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ card_image: nextCard, director: nextDirector }),
  });
  centersUpdated++;
  console.log(`  ${c.slug}: card_image -> ${nextCard}, director.photo -> ${nextDirector ? nextDirector.photo : null}`);
}
console.log(`centers: ${centersUpdated}/${centers.length} rows updated`);
