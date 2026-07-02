import { readFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Disabled: the haetsal demo image seed used shared haetsal/* paths.
// Storage now starts clean and new uploads must use centers/{center_id}/...
console.error('Disabled: legacy haetsal demo image seed is no longer used. Use the admin UI with centers/{center_id}/ paths.');
process.exit(1);

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const configText = await readFile(path.join(projectRoot, 'supabase-config.js'), 'utf8');

const url = configText.match(/url:\s*'([^']+)'/)?.[1];
const anonKey = configText.match(/anonKey:\s*'([^']+)'/)?.[1];
if (!url || !anonKey) throw new Error('Could not read Supabase config.');
const apiKey = process.env.SUPABASE_SERVICE_ROLE_KEY || anonKey;
const keyLabel = process.env.SUPABASE_SERVICE_ROLE_KEY ? 'service role key' : 'anon key';

const bucket = 'center-images';
const assetRoot = path.join(projectRoot, 'generated', 'center-images');

const assets = [
  ['haetsal/director/director_1.jpg', 'haetsal/director/director_1.jpg'],
  ['haetsal/teacher/teacher_1.jpg', 'haetsal/teacher/teacher_1.jpg'],
  ['haetsal/teacher/teacher_2.jpg', 'haetsal/teacher/teacher_2.jpg'],
  ['haetsal/teacher/teacher_3.jpg', 'haetsal/teacher/teacher_3.jpg'],
  ['haetsal/day_story/morning.jpg', 'haetsal/day_story/morning.jpg'],
  ['haetsal/day_story/mid_morning.jpg', 'haetsal/day_story/mid_morning.jpg'],
  ['haetsal/day_story/noon.jpg', 'haetsal/day_story/noon.jpg'],
  ['haetsal/day_story/nap.jpg', 'haetsal/day_story/nap.jpg'],
  ['haetsal/day_story/outdoor.jpg', 'haetsal/day_story/outdoor.jpg'],
  ['haetsal/album/block_play.jpg', 'haetsal/album/block_play.jpg'],
  ['haetsal/album/finger_painting.jpg', 'haetsal/album/finger_painting.jpg'],
  ['haetsal/album/book_reading.jpg', 'haetsal/album/book_reading.jpg'],
  ['haetsal/album/rice_ball_cooking.jpg', 'haetsal/album/rice_ball_cooking.jpg'],
  ['haetsal/album/spring_picnic.jpg', 'haetsal/album/spring_picnic.jpg'],
  ['haetsal/album/music_dance.jpg', 'haetsal/album/music_dance.jpg'],
  ['haetsal/album/seed_planting.jpg', 'haetsal/album/seed_planting.jpg'],
  ['haetsal/album/birthday_party.jpg', 'haetsal/album/birthday_party.jpg'],
  ['haetsal/album/sports_day_race.jpg', 'haetsal/album/sports_day_race.jpg'],
  ['haetsal/album/stretching.jpg', 'haetsal/album/stretching.jpg'],
  ['haetsal/album/show_drawing.jpg', 'haetsal/album/show_drawing.jpg'],
  ['haetsal/album/graduation.jpg', 'haetsal/album/graduation.jpg'],
];

const dayStory = [
  { sort_order: 0, slot: 'morning', photo_url: 'haetsal/day_story/morning.jpg' },
  { sort_order: 1, slot: 'mid-morning', photo_url: 'haetsal/day_story/mid_morning.jpg' },
  { sort_order: 2, slot: 'noon', photo_url: 'haetsal/day_story/noon.jpg' },
  { sort_order: 3, slot: 'afternoon', photo_url: 'haetsal/day_story/nap.jpg' },
  { sort_order: 4, slot: 'dusk', photo_url: 'haetsal/day_story/outdoor.jpg' },
];

const teachers = [
  { sort_order: 0, photo_url: 'haetsal/teacher/teacher_1.jpg' },
  { sort_order: 1, photo_url: 'haetsal/teacher/teacher_2.jpg' },
  { sort_order: 2, photo_url: 'haetsal/teacher/teacher_3.jpg' },
];

const album = [
  ['블록 쌓기 놀이', 'haetsal/album/block_play.jpg'],
  ['핑거페인팅', 'haetsal/album/finger_painting.jpg'],
  ['그림책 읽기', 'haetsal/album/book_reading.jpg'],
  ['주먹밥 만들기', 'haetsal/album/rice_ball_cooking.jpg'],
  ['봄 소풍', 'haetsal/album/spring_picnic.jpg'],
  ['율동과 노래', 'haetsal/album/music_dance.jpg'],
  ['씨앗 심기', 'haetsal/album/seed_planting.jpg'],
  ['생일 파티', 'haetsal/album/birthday_party.jpg'],
  ['운동회 달리기', 'haetsal/album/sports_day_race.jpg'],
  ['스트레칭 체조', 'haetsal/album/stretching.jpg'],
  ['그림 자랑', 'haetsal/album/show_drawing.jpg'],
  ['졸업식', 'haetsal/album/graduation.jpg'],
].map(([title, photo_url], sort_order) => ({ sort_order, title, photo_url, photo_alt: title }));

function authHeaders(extra = {}) {
  return {
    apikey: apiKey,
    Authorization: `Bearer ${apiKey}`,
    ...extra,
  };
}

async function request(endpoint, options = {}) {
  const res = await fetch(`${url}${endpoint}`, {
    ...options,
    headers: authHeaders(options.headers),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${options.method || 'GET'} ${endpoint} failed (${res.status}): ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

async function uploadObject(storagePath, localRel) {
  const localPath = path.join(assetRoot, localRel);
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
}

async function updateRows(centerId, mediaType, rows) {
  const existing = await request(`/rest/v1/center_media?center_id=eq.${centerId}&media_type=eq.${mediaType}&select=*`);
  for (const row of rows) {
    const current = existing.find((item) => item.sort_order === row.sort_order);
    if (current) {
      await request(`/rest/v1/center_media?id=eq.${current.id}`, {
        method: 'PATCH',
        headers: { 'content-type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify(row),
      });
    } else {
      await request('/rest/v1/center_media', {
        method: 'POST',
        headers: { 'content-type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({
          center_id: centerId,
          media_type: mediaType,
          ...row,
        }),
      });
    }
  }
}

console.log(`Using ${keyLabel}. Uploading ${assets.length} images to ${bucket}...`);
for (const [storagePath, localRel] of assets) {
  await uploadObject(storagePath, localRel);
  console.log(`uploaded ${storagePath}`);
}

const [center] = await request('/rest/v1/centers?slug=eq.haetsal&select=id,director');
if (!center) throw new Error("No center found for slug 'haetsal'.");

// centers 업데이트는 불필요 (이미지는 center_media에 이미 반영됨) — director.photo PATCH 건너뜀
// await request('/rest/v1/centers?slug=eq.haetsal', {
//   method: 'PATCH',
//   headers: { 'content-type': 'application/json', Prefer: 'return=minimal' },
//   body: JSON.stringify({
//     director: {
//       ...(center.director || {}),
//       photo: 'haetsal/director/director_1.jpg',
//     },
//   }),
// });

await updateRows(center.id, 'day_story', dayStory);
await updateRows(center.id, 'teacher', teachers);
await updateRows(center.id, 'album', album);

console.log('Applied haetsal demo images.');
