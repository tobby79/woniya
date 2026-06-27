-- Fill teacher card text for published demo centers.
-- The front end reads center_media.title as teacher name,
-- center_media.subtitle as role, and center_media.caption as card message.

begin;

with teacher_text(sort_order, title, subtitle, caption) as (
  values
    (0, '김햇살 선생님', '만 3세 햇살반 담임', '"아이의 속도에<br>맞춰 기다려 줄게요."'),
    (1, '이초록 선생님', '만 4세 새싹반 담임', '"매일의 작은 성장을<br>놓치지 않을게요."'),
    (2, '박노을 선생님', '만 5세 열매반 담임', '"마음껏 궁금해하는<br>아이로 도울게요."')
)
update center_media cm
set
  title = teacher_text.title,
  subtitle = teacher_text.subtitle,
  caption = teacher_text.caption
from centers c, teacher_text
where cm.center_id = c.id
  and cm.media_type = 'teacher'
  and cm.sort_order = teacher_text.sort_order
  and c.slug in ('haetsal', 'gallery', 'soop', 'carnival');

commit;
