# 원이야 M1 — 데이터화 (햇살가득 데모)

하드코딩 홈페이지를 **데이터(JSON) + 템플릿(HTML)** 으로 분리한 첫 MVP 결과물입니다.

## 폴더 구성
- `template-sunshine.html` — 화면 템플릿. `haetsal.json`을 읽어 모든 섹션을 그립니다. (디자인·애니메이션 원본 유지)
- `haetsal.json` — 원 데이터. 9번 데이터 모델 구조에 맞춰 분리.
- `img/` — 원본에 박혀있던 사진 15개를 파일로 추출. JSON엔 경로만 둠.

## 실행 방법
브라우저에서 `template-sunshine.html`을 그냥 열면 `fetch`가 막힙니다. 로컬 서버로 여세요.
```
cd woniya-m1
python3 -m http.server 8000
# 브라우저: http://localhost:8000
```
(Vercel·일반 호스팅에 올리면 그대로 동작합니다.)

## 다른 원 추가해보기
`haetsal.json`만 복사해서 값을 바꾸면 됩니다. 화면 코드는 손대지 않습니다.
이게 "빌더"의 뼈대 — 원장은 데이터만 넣으면 완성.

## 다음 단계: Supabase 연결
`template-sunshine.html` 안의 데이터 호출 한 줄만 바꾸면 됩니다.
```js
// 지금
const res = await fetch('haetsal.json');
const data = await res.json();

// 나중 (Supabase)
const { data } = await supabase.from('centers')
  .select('*, center_media(*), classes(*) ...')
  .eq('id', 원ID).single();
```
JSON 키 이름을 DB 컬럼명과 맞춰두었기 때문에, 화면 렌더 코드는 거의 그대로 재사용됩니다.

## JSON ↔ 데이터 모델 매핑
| JSON 키 | 대응 테이블(9번) |
|---|---|
| `center` | centers |
| `day_story` / `album` / `teachers` | center_media (type 구분) |
| `schedule.events` | events(또는 letters) |
| `notices` / `faqs` | 원 콘텐츠 필드 |
