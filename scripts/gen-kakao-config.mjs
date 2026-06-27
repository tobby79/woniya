// Vercel 빌드 시 실행되어 kakao-config.js를 생성한다.
// 카카오맵 JavaScript 키는 소스에 하드코딩하지 않고 Vercel 환경변수
// KAKAO_MAP_API_KEY 에서 주입한다(= Supabase 키와 동일한 "런타임 config.js" 패턴,
// 단 키 값은 커밋하지 않고 빌드 시 생성). 생성물은 .gitignore 처리됨.
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const outPath = path.join(projectRoot, 'kakao-config.js');

const key = process.env.KAKAO_MAP_API_KEY || '';
if (!key) {
  console.warn('[gen-kakao-config] KAKAO_MAP_API_KEY 환경변수가 비어 있습니다 — 지도가 렌더되지 않습니다.');
}

const body = [
  '// 자동 생성 파일 — scripts/gen-kakao-config.mjs 가 빌드 시 생성합니다.',
  '// 직접 수정/커밋하지 마세요 (.gitignore 처리). 키는 Vercel 환경변수에서 주입됩니다.',
  'window.__KAKAO_CONFIG__ = { appkey: ' + JSON.stringify(key) + ' };',
  '',
].join('\n');

writeFileSync(outPath, body, 'utf8');
console.log('[gen-kakao-config] kakao-config.js 생성 완료 (appkey ' + (key ? 'present' : 'MISSING') + ').');
