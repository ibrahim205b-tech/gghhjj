-- Security & behaviour tests. Run against a database with migrations + seed
-- applied:  psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql
-- Every check raises an exception on failure.

\set ON_ERROR_STOP 1
begin;

-- Fixtures (as superuser) ----------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test', '{"full_name":"Admin"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'ali@test',   '{"full_name":"علي"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'sara@test',  '{"full_name":"سارة"}');
insert into public.admin_roles (user_id, role) values ('00000000-0000-0000-0000-00000000000a', 'super_admin');

do $$ begin
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a1') = 'علي',
    'profile auto-created from Google metadata';
end $$;

-- grade_12 applied for Ali, grade_7 for Sara
insert into public.student_academic_profiles (user_id, stage_id, grade_id, branch_id)
select '00000000-0000-0000-0000-0000000000a1', g.stage_id, g.id, b.id
from public.grades g join public.academic_branches b on b.grade_id = g.id and b.code = 'applied' where g.code = 'grade_12';
insert into public.student_academic_profiles (user_id, stage_id, grade_id)
select '00000000-0000-0000-0000-0000000000b2', stage_id, id from public.grades where code = 'grade_7';

-- branch is mandatory for preparatory grades
do $$ begin
  begin
    insert into public.student_academic_profiles (user_id, stage_id, grade_id)
    select '00000000-0000-0000-0000-00000000000a', stage_id, id from public.grades where code = 'grade_11';
    raise exception 'FAIL: grade_11 without branch accepted';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

create temp table ids (k text primary key, v uuid);
grant select on ids to authenticated;

-- Content as admin --------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

insert into public.subjects (grade_id, name_ar) select id, 'الرياضيات' from public.grades where code = 'grade_12';
insert into public.subjects (grade_id, name_ar) select id, 'العلوم' from public.grades where code = 'grade_7';

insert into public.questions (grade_id, subject_id, question_type, question_text, status)
select s.grade_id, s.id, 'true_false', 'published g12', 'published' from public.subjects s where s.name_ar = 'الرياضيات';
insert into public.questions (grade_id, subject_id, question_type, question_text, status)
select s.grade_id, s.id, 'true_false', 'draft g12', 'draft' from public.subjects s where s.name_ar = 'الرياضيات';
insert into public.questions (grade_id, subject_id, question_type, question_text, status, publish_at)
select s.grade_id, s.id, 'true_false', 'scheduled future', 'scheduled', now() + interval '1 day' from public.subjects s where s.name_ar = 'الرياضيات';
insert into public.questions (grade_id, subject_id, question_type, question_text, status, publish_at)
select s.grade_id, s.id, 'true_false', 'scheduled past', 'scheduled', now() - interval '1 minute' from public.subjects s where s.name_ar = 'الرياضيات';
insert into public.questions (grade_id, subject_id, question_type, question_text, status, expires_at)
select s.grade_id, s.id, 'true_false', 'expired', 'published', now() - interval '1 minute' from public.subjects s where s.name_ar = 'الرياضيات';
insert into public.questions (grade_id, subject_id, question_type, question_text, status)
select s.grade_id, s.id, 'true_false', 'published g7', 'published' from public.subjects s where s.name_ar = 'العلوم';

insert into public.question_options (question_id, option_text, is_correct)
select id, 'صح', true from public.questions where question_text = 'published g12';
insert into public.question_options (question_id, option_text, is_correct)
select id, 'صح', true from public.questions where question_text = 'draft g12';

insert into public.announcements (title, status, target_all) values ('للكل', 'published', true);
insert into public.announcements (title, status, target_all) values ('للمتوسط فقط', 'published', false);
insert into public.announcement_targets (announcement_id, grade_id)
select a.id, g.id from public.announcements a, public.grades g where a.title = 'للمتوسط فقط' and g.code = 'grade_7';

insert into public.daily_motivations (body, status, target_grade_ids)
select 'تحفيز السادس', 'published', array[id] from public.grades where code = 'grade_12';

do $$ begin
  assert (select count(*) from public.admin_activity_logs where entity_type = 'questions') >= 6,
    'admin changes are written to the activity log';
end $$;
reset role;

-- Student Ali (grade 12 applied) ------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
set local role authenticated;
do $$
declare v text[];
begin
  select array_agg(question_text order by question_text) into v from public.questions;
  assert v = array['published g12', 'scheduled past'], format('student sees only live questions of own grade, got %s', v);
  assert (select count(*) from public.question_options) = 1, 'options of hidden questions are hidden';
  assert (select count(*) from public.announcements) = 1, 'grade-targeted announcement hidden from other grades';
  assert (select count(*) from public.daily_motivations) = 1, 'motivation targeted to own grade visible';
  assert (select count(*) from public.admin_activity_logs) = 0, 'students cannot read activity logs';
  assert (select count(*) from public.profiles) = 1, 'students only see their own profile';
  assert (select count(*) from public.student_academic_profiles) = 1, 'only own academic profile';
end $$;

insert into public.study_tasks (id, title, client_modified_at)
values ('11111111-1111-1111-1111-111111111111', 'مراجعة الفصل الأول', '2026-11-22 10:00+03');
-- older write from another device must not overwrite the newer one
update public.study_tasks set title = 'old title', client_modified_at = '2026-11-22 09:00+03'
where id = '11111111-1111-1111-1111-111111111111';
do $$ begin
  assert (select title from public.study_tasks where id = '11111111-1111-1111-1111-111111111111') = 'مراجعة الفصل الأول',
    'last-write-wins keeps the newer copy';
end $$;

do $$ begin
  begin
    insert into public.questions (grade_id, subject_id, question_type, question_text)
    select grade_id, id, 'true_false', 'hack' from public.subjects limit 1;
    raise exception 'FAIL: student inserted a question';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.admin_roles (user_id, role) values (auth.uid(), 'super_admin');
    raise exception 'FAIL: student granted admin';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_overview();
    raise exception 'FAIL: student read admin overview';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.profiles set status = 'active', suspended_reason = 'x' where id = auth.uid();
    raise exception 'FAIL: student changed moderation field';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    insert into public.exams (title, exam_at, is_official, grade_id) values ('fake official', now(), true, public.my_grade_id());
    raise exception 'FAIL: student created official exam';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;
insert into public.exams (user_id, title, exam_at) values (auth.uid(), 'امتحاني', now() + interval '3 days');
reset role;

-- Student Sara cannot see Ali's data ------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
set local role authenticated;
do $$ begin
  assert (select count(*) from public.study_tasks) = 0, 'other students'' tasks are invisible';
  assert (select count(*) from public.exams) = 0, 'other students'' exams are invisible';
  assert (select array_agg(question_text) from public.questions) = array['published g7'], 'grade 7 sees its own questions';
  assert (select count(*) from public.announcements) = 2, 'grade 7 sees all + grade 7 announcements';
  assert (select count(*) from public.daily_motivations) = 0, 'grade 12 motivation hidden from grade 7';
  update public.study_tasks set title = 'x';  -- affects 0 rows silently
  perform public.mark_announcement_seen((select id from public.announcements where title = 'للكل'), true);
  assert (select acknowledged from public.announcement_acknowledgments) , 'acknowledgment recorded';
end $$;
reset role;

-- Suspension blocks writes -----------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
set local role authenticated;
select public.admin_set_student_status('00000000-0000-0000-0000-0000000000a1', 'suspended', 'test');
do $$ begin
  assert (select (public.admin_overview() ->> 'students_total')::int) = 2, 'overview counts students (not admins)';
  assert (select count(*) from public.admin_list_students()) = 2, 'admin lists students';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
set local role authenticated;
do $$ begin
  begin
    insert into public.study_tasks (id, title) values (gen_random_uuid(), 'blocked');
    raise exception 'FAIL: suspended student wrote data';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Scheduled publishing job -----------------------------------------------------------
do $$
declare r jsonb := public.publish_due_content();
begin
  assert (r ->> 'published')::int >= 1 and (r ->> 'expired')::int >= 1, format('publisher flips statuses: %s', r);
  assert (select status from public.questions where question_text = 'scheduled past') = 'published', 'scheduled -> published';
  assert (select status from public.questions where question_text = 'expired') = 'expired', 'published -> expired';
  assert (select status from public.questions where question_text = 'scheduled future') = 'scheduled', 'future stays scheduled';
end $$;

-- Account deletion cascades every personal row ----------------------------------------------
delete from auth.users where id = '00000000-0000-0000-0000-0000000000a1';
do $$ begin
  assert (select count(*) from public.study_tasks) = 0 and (select count(*) from public.exams where not is_official) = 0,
    'deleting the auth user removes personal data';
end $$;

select 'ALL RLS TESTS PASSED' as result;
rollback;
