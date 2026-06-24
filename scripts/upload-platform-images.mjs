import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const configText = await readFile(path.join(projectRoot, 'supabase-config.js'), 'utf8');

const url = configText.match(/url:\s*'([^']+)'/)?.[1];
const anonKey = configText.match(/anonKey:\s*'([^']+)'/)?.[1];
if (!url || !anonKey) throw new Error('Could not read Supabase config.');

const apiKey = process.env.SUPABASE_SERVICE_ROLE_KEY || anonKey;
const keyLabel = process.env.SUPABASE_SERVICE_ROLE_KEY ? 'service role key' : 'anon key';
const bucket = 'center-images';
const assetRoot = path.join(projectRoot, 'generated', 'platform-images');

const uploads = [
  'card/haetsal.jpg',
  'card/soop.jpg',
  'card/carnival.jpg',
  'card/gallery.jpg',
  'hero/gallery_exterior.jpg',
];

function authHeaders(extra = {}) {
  return {
    apikey: apiKey,
    Authorization: `Bearer ${apiKey}`,
    ...extra,
  };
}

async function uploadObject(storagePath) {
  const localPath = path.join(assetRoot, storagePath);
  const size = (await stat(localPath)).size;
  const res = await fetch(`${url}/storage/v1/object/${bucket}/${storagePath}`, {
    method: 'POST',
    headers: authHeaders({
      'content-type': 'image/jpeg',
      'content-length': String(size),
      'cache-control': '3600',
      'x-upsert': 'true',
    }),
    body: createReadStream(localPath),
    duplex: 'half',
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`upload ${storagePath} failed (${res.status}): ${text}`);
  return text ? JSON.parse(text) : null;
}

console.log(`Using ${keyLabel}. Uploading ${uploads.length} images to ${bucket}...`);
for (const storagePath of uploads) {
  await uploadObject(storagePath);
  console.log(`uploaded ${storagePath}`);
}
console.log('Done.');
