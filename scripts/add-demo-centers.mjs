import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const configText = await readFile(path.join(projectRoot, 'supabase-config.js'), 'utf8');

const url = configText.match(/url:\s*'([^']+)'/)?.[1];
const anonKey = configText.match(/anonKey:\s*'([^']+)'/)?.[1];
if (!url || !anonKey) throw new Error('Could not read Supabase config.');
const apiKey = process.env.SUPABASE_SERVICE_ROLE_KEY || anonKey;
const keyLabel = process.env.SUPABASE_SERVICE_ROLE_KEY ? 'service role key' : 'anon key';

function authHeaders(extra = {}) {
  return { apikey: apiKey, Authorization: `Bearer ${apiKey}`, ...extra };
}

async function request(endpoint, options = {}) {
  const res = await fetch(`${url}${endpoint}`, { ...options, headers: authHeaders(options.headers) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${options.method || 'GET'} ${endpoint} failed (${res.status}): ${text}`);
  return text ? JSON.parse(text) : null;
}

// haetsal 행을 본떠서 만든 공통 구조 (menu/notices/schedule/faqs/finale/footer/badges/tags는 데모용으로 동일하게 재사용)
const MENU = [
  { href: '#day', label: '우리 원의 하루' },
  { href: '#notice', label: '공지사항' },
  { href: '#schedule', label: '행사 일정' },
  { href: '#faq', label: '자주 묻는 질문' },
  { cta: true, href: '#finale', label: '입소 상담' },
];

const NOTICES = {
  eyebrow: '알려드려요',
  title: '공지사항',
  more: '공지 전체 보기',
  items: [
    { tag: '행사', tag_type: 'event', title: '여름 물놀이의 날 안내', date: '2025. 6. 10.' },
    { tag: '필독', tag_type: 'must', title: '6월 학부모 상담주간 신청 안내', date: '2025. 6. 5.' },
    { tag: '안내', tag_type: 'info', title: '차량 운행 노선 변경 안내', date: '2025. 6. 2.' },
  ],
};

const SCHEDULE = {
  eyebrow: '이번 달 이야기',
  title: '행사 일정',
  month_label: '2025년 6월',
  first_dow: 0,
  days_in_month: 30,
  trailing_muted: 5,
  event_days: [10, 18, 27],
  events: [
    { date: '06.10', title: '여름 물놀이의 날' },
    { date: '06.18', title: '학부모 상담주간 시작' },
    { date: '06.27', title: '6월 생일잔치' },
  ],
};

const FAQS = {
  eyebrow: '궁금해요',
  title: '자주 묻는 질문',
  items: [
    { q: '입소 신청은 어떻게 하나요?', a: '홈페이지 상단의 입소 상담 버튼으로 신청하시면, 원에서 연락드려 상담 일정을 잡아드려요. 대기 순번과 빈자리 현황도 함께 안내해 드립니다.' },
    { q: '차량 운행은 어디까지 되나요?', a: '원 반경 약 2km 내 주요 단지를 운행하고 있어요. 노선과 시간은 공지사항에서 확인하실 수 있고, 자세한 정류장은 상담 시 안내해 드립니다.' },
    { q: '식단과 알레르기 관리는 어떻게 하나요?', a: '영양사가 매월 식단을 구성하고 매일 사진으로 공유해 드려요. 알레르기가 있는 아이는 입소 시 미리 알려주시면 대체 식단으로 따로 챙깁니다.' },
    { q: '하루 일과와 등·하원 시간이 궁금해요.', a: '등원은 오전 9시 전후, 하원은 오후 4시가 기본이에요. 맞벌이 가정을 위한 시간 연장 보육도 운영하니 편하게 문의해 주세요.' },
  ],
};

const FOOTER = { tag: '데모 템플릿', text: '실제 사진·문구·원 이름을 넣으면 그대로 완성됩니다.' };
const BADGES = { licensed: true, cctv: true, meal_open: true, shuttle: true, extended_care: false, evaluated: true };
const TAGS = ['소규모', '시간연장', '유기농 급식'];

function makeDirector(name) {
  return {
    badge: '원장 인사말',
    photo: null,
    photo_alt: '원장님',
    message: '"한 아이를 키우려면<br>온 마음이 필요하다고 믿어요.<br>우리 원은 그 마음으로<br>아이의 오늘을 함께합니다."',
    sign_name: '○ ○ ○',
    sign_label: `${name} 원장`,
    scroll_cue: '스크롤해서 하루를 따라가 보세요',
  };
}

// soop / carnival / gallery 3개 데모 원
const NEW_CENTERS = [
  {
    slug: 'soop',
    name: '초록숲 어린이집',
    region: '서울 마포구',
    address: '서울 마포구 숲길 5',
    template: 'forest',
    hero: { eyebrow: '아이의 하루가 자라는 곳', title: '초록숲', title_accent: '어린이집', subtitle: '숲을 닮은 공간에서,<br>아이가 자연과 함께 자라는 하루를 들여다보세요.' },
  },
  {
    slug: 'carnival',
    name: '무지개 유치원',
    region: '서울 송파구',
    address: '서울 송파구 놀이로 7',
    template: 'carnival',
    hero: { eyebrow: '매일이 즐거운 놀이동산', title: '무지개', title_accent: '유치원', subtitle: '알록달록한 하루 속에서,<br>아이가 신나게 웃는 순간을 함께 만나보세요.' },
  },
  {
    slug: 'gallery',
    name: '갤러리아 유치원',
    region: '서울 강남구',
    address: '서울 강남구 예술로 3',
    template: 'gallery',
    hero: { eyebrow: '예술처럼 자라는 시간', title: '갤러리아', title_accent: '유치원', subtitle: '한 장의 사진처럼,<br>아이의 하루를 차분하게 담아냅니다.' },
  },
];

// 4개 원(haetsal 포함)에 공통으로 채울 center_media. 이미지는 haetsal용으로 올려둔 동일 경로를 공유한다.
const DAY_STORY = [
  { sort_order: 0, slot: 'morning', time_label: '오전 9:00', title: '등원 및 아침 활동', photo_url: 'haetsal/day_story/morning.jpg', photo_alt: '등원하는 아이들', caption: '안녕, 오늘도 반가워!', note: '이름 모음, 실내화 갈아신기 등 천천히 하루를 시작해요.' },
  { sort_order: 1, slot: 'mid-morning', time_label: '오전 10:30', title: '오전 놀이 활동', photo_url: 'haetsal/day_story/mid_morning.jpg', photo_alt: '오전 놀이 활동', caption: '오늘은 무슨 놀이를 할까?', note: '주제별 놀이와 활동으로 오전 시간을 보내요.' },
  { sort_order: 2, slot: 'noon', time_label: '낮 12:00', title: '점심 식사', photo_url: 'haetsal/day_story/noon.jpg', photo_alt: '점심 식사 시간', caption: '맛있게 먹는 시간', note: '영양사가 구성한 균형 잡힌 식단으로 점심을 먹어요.' },
  { sort_order: 3, slot: 'afternoon', time_label: '오후 1:30', title: '낮잠 시간', photo_url: 'haetsal/day_story/nap.jpg', photo_alt: '낮잠 자는 아이들', caption: '쉿, 잠든 시간', note: '오후 활동을 위해 푹 쉬는 시간을 가져요.' },
  { sort_order: 4, slot: 'dusk', time_label: '오후 3:30', title: '바깥 놀이 및 하원', photo_url: 'haetsal/day_story/outdoor.jpg', photo_alt: '바깥 놀이 하는 아이들', caption: '내일 또 만나요!', note: '바깥 놀이를 마치고 안전하게 하원 준비를 해요.' },
];

const TEACHERS = [
  { sort_order: 0, title: '김민지', subtitle: '반 담임 교사', photo_url: 'haetsal/teacher/teacher_1.jpg', caption: '아이들과 눈을 맞추는 게 제일 좋아요.' },
  { sort_order: 1, title: '이서윤', subtitle: '반 담임 교사', photo_url: 'haetsal/teacher/teacher_2.jpg', caption: '작은 변화도 놓치지 않고 살펴볼게요.' },
  { sort_order: 2, title: '박지호', subtitle: '체육·놀이 교사', photo_url: 'haetsal/teacher/teacher_3.jpg', caption: '몸으로 신나게 노는 시간, 제가 함께해요.' },
];

const ALBUM = [
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

async function upsertMedia(centerId, mediaType, rows) {
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
        body: JSON.stringify({ center_id: centerId, media_type: mediaType, ...row }),
      });
    }
  }
}

console.log(`Using ${keyLabel}.`);

// 1) haetsal id 조회 (이미 있는 원 — center_media만 같이 채워준다)
const [haetsal] = await request('/rest/v1/centers?slug=eq.haetsal&select=id');
if (!haetsal) throw new Error("No center found for slug 'haetsal'.");

// 2) soop / carnival / gallery 3개 원 INSERT (이미 있으면 건너뜀)
const centerIds = { haetsal: haetsal.id };
for (const nc of NEW_CENTERS) {
  const [existing] = await request(`/rest/v1/centers?slug=eq.${nc.slug}&select=id`);
  if (existing) {
    console.log(`centers: '${nc.slug}' already exists, skip insert.`);
    centerIds[nc.slug] = existing.id;
    continue;
  }
  const payload = {
    owner_id: crypto.randomUUID(), // 주의: centers.owner_id가 auth.users를 FK로 참조한다면 이 값은 실패합니다 (아래 안내 참고)
    slug: nc.slug,
    name: nc.name,
    region: nc.region,
    address: nc.address,
    theme: 'pink',
    template: nc.template,
    status: 'published',
    menu: MENU,
    hero: nc.hero,
    director: makeDirector(nc.name),
    notices: NOTICES,
    schedule: SCHEDULE,
    faqs: FAQS,
    finale: { title: '우리 아이의 하루,<br>이제 직접 보여드릴게요', subtitle: '언제든 편하게 둘러보러 오세요.<br>상담 신청은 1분이면 충분해요.', cta: '입소 상담 신청하기' },
    footer: FOOTER,
    badges: BADGES,
    tags: TAGS,
    intro: '데모용으로 등록된 원입니다.',
    operating_hours: '',
  };
  const [inserted] = await request('/rest/v1/centers', {
    method: 'POST',
    headers: { 'content-type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify(payload),
  });
  centerIds[nc.slug] = inserted.id;
  console.log(`centers: inserted '${nc.slug}' -> ${inserted.id}`);
}

// 3) 4개 원(haetsal + 3개 신규) 모두에 동일한 데모 이미지로 center_media 채우기
for (const slug of Object.keys(centerIds)) {
  const id = centerIds[slug];
  await upsertMedia(id, 'day_story', DAY_STORY);
  await upsertMedia(id, 'teacher', TEACHERS);
  await upsertMedia(id, 'album', ALBUM);
  console.log(`center_media: synced for '${slug}'`);
}

console.log('Done.');
