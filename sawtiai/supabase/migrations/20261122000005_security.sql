-- Row Level Security, storage policies, RPCs and scheduled publishing.
-- Authorization is enforced HERE (server side). The admin dashboard hiding a
-- button is never the only protection.

create or replace function public.is_admin_or_above() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_roles where user_id = auth.uid() and role in ('admin', 'super_admin'))
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Profiles / admin roles / logs
-- ---------------------------------------------------------------------------
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_insert_self on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (public.is_admin_or_above()) with check (public.is_admin_or_above());

create policy admin_roles_select on public.admin_roles for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy admin_roles_write on public.admin_roles for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin() and user_id <> auth.uid());

create policy admin_logs_select on public.admin_activity_logs for select to authenticated
  using (public.is_admin());
-- no insert/update/delete policies: only the security-definer trigger writes.

-- ---------------------------------------------------------------------------
-- Academic reference data: readable by signed-in users, writable by admins
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['academic_stages','grades','academic_branches','academic_years','subjects',
                           'chapters','topics','library_categories'] loop
    execute format('create policy %1$s_read on public.%1$s for select to authenticated
                    using (public.is_admin() or (deleted_at is null and is_active))', t);
    execute format('create policy %1$s_admin on public.%1$s for all to authenticated
                    using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

create policy sap_own on public.student_academic_profiles for all to authenticated
  using (user_id = auth.uid() and public.is_active_user())
  with check (user_id = auth.uid() and public.is_active_user());
create policy sap_admin_read on public.student_academic_profiles for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Student-owned data: only the owner (admins do NOT read personal study data)
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['student_subject_progress','study_schedules','study_sessions','study_tasks',
                           'student_notes','student_goals','student_achievements','student_expenses',
                           'study_logs','user_preferences','device_tokens','sync_metadata',
                           'exam_attempts','student_answers','saved_questions'] loop
    execute format('create policy %1$s_own on public.%1$s for all to authenticated
                    using (user_id = auth.uid() and public.is_active_user())
                    with check (user_id = auth.uid() and public.is_active_user())', t);
  end loop;
end $$;

-- Exams: personal rows are owned by the student; official rows are admin-managed.
create policy exams_read on public.exams for select to authenticated
  using (public.is_admin()
         or (user_id = auth.uid())
         or (is_official and deleted_at is null and public.is_live(status, publish_at, expires_at)
             and public.targets_me(grade_id, branch_id)));
create policy exams_student_write on public.exams for insert to authenticated
  with check (user_id = auth.uid() and not is_official and public.is_active_user());
create policy exams_student_update on public.exams for update to authenticated
  using (user_id = auth.uid() and not is_official) with check (user_id = auth.uid() and not is_official);
create policy exams_student_delete on public.exams for delete to authenticated
  using (user_id = auth.uid() and not is_official);
create policy exams_admin on public.exams for all to authenticated
  using (public.is_admin() and is_official) with check (public.is_admin() and is_official);

-- ---------------------------------------------------------------------------
-- Published content
-- ---------------------------------------------------------------------------
create policy questions_read on public.questions for select to authenticated
  using (public.is_admin()
         or (deleted_at is null and public.is_live(status, publish_at, expires_at)
             and public.targets_me(grade_id, branch_id)));
create policy questions_admin on public.questions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy question_options_read on public.question_options for select to authenticated
  using (public.is_admin() or exists (select 1 from public.questions q where q.id = question_id));
  -- (the subquery is itself filtered by questions_read)
create policy question_options_admin on public.question_options for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy library_files_read on public.library_files for select to authenticated
  using (public.is_admin()
         or (deleted_at is null and public.is_live(status, publish_at, expires_at)
             and public.targets_me(grade_id, branch_id)));
create policy library_files_admin on public.library_files for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy file_downloads_insert on public.file_downloads for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.library_files f where f.id = file_id));
create policy file_downloads_admin on public.file_downloads for select to authenticated
  using (public.is_admin());

create policy motivations_read on public.daily_motivations for select to authenticated
  using (public.is_admin()
         or (deleted_at is null and public.is_live(status, publish_at, expires_at)
             and public.targets_me_arrays(target_grade_ids, target_branch_ids, target_stage_ids)));
create policy motivations_admin on public.daily_motivations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy announcements_read on public.announcements for select to authenticated
  using (public.is_admin()
         or (deleted_at is null and public.is_live(status, publish_at, expires_at)
             and public.announcement_targets_me(id, target_all)));
create policy announcements_admin on public.announcements for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy announcement_targets_read on public.announcement_targets for select to authenticated
  using (true);
create policy announcement_targets_admin on public.announcement_targets for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy announcement_acks_own on public.announcement_acknowledgments for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy announcement_acks_admin on public.announcement_acknowledgments for select to authenticated
  using (public.is_admin());

create policy campaigns_admin on public.notification_campaigns for all to authenticated
  using (public.is_admin()) with check (public.is_admin() and (audience <> 'user' or public.is_admin_or_above()));
create policy recipients_admin on public.notification_recipients for select to authenticated
  using (public.is_admin());

create policy universities_read on public.universities for select to authenticated
  using (public.is_admin() or (deleted_at is null and public.is_live(status, publish_at, expires_at)));
create policy universities_admin on public.universities for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy colleges_read on public.colleges for select to authenticated
  using (public.is_admin() or (deleted_at is null and exists (select 1 from public.universities u where u.id = university_id)));
create policy colleges_admin on public.colleges for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy specializations_read on public.specializations for select to authenticated
  using (public.is_admin() or (deleted_at is null and exists (select 1 from public.colleges c where c.id = college_id)));
create policy specializations_admin on public.specializations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admission_read on public.admission_information for select to authenticated
  using (public.is_admin() or (deleted_at is null and public.is_live(status, publish_at, expires_at)));
create policy admission_admin on public.admission_information for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Version info is also readable before sign-in (update prompts on first launch).
create policy app_versions_read on public.app_versions for select to anon, authenticated
  using (public.is_live(status, publish_at, expires_at) or public.is_admin());
create policy app_versions_admin on public.app_versions for all to authenticated
  using (public.is_admin_or_above()) with check (public.is_admin_or_above());
create policy app_settings_read on public.app_settings for select to anon, authenticated
  using (is_public or public.is_admin());
create policy app_settings_admin on public.app_settings for all to authenticated
  using (public.is_admin_or_above()) with check (public.is_admin_or_above());

-- ---------------------------------------------------------------------------
-- Grants (Supabase roles)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on public.app_versions, public.app_settings to anon;
revoke insert, update, delete on public.admin_activity_logs from authenticated;
grant execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Dashboard numbers for administrators.
create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'students_total', (select count(*) from public.profiles p where not exists (select 1 from public.admin_roles a where a.user_id = p.id)),
    'students_active_7d', (select count(*) from public.profiles p where p.last_seen_at > now() - interval '7 days'
                             and not exists (select 1 from public.admin_roles a where a.user_id = p.id)),
    'students_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'by_grade', coalesce((select jsonb_agg(jsonb_build_object('grade_id', g.id, 'name', g.name_ar, 'count', c.n) order by g.sort_order)
                           from public.grades g
                           join (select grade_id, count(*) n from public.student_academic_profiles group by grade_id) c on c.grade_id = g.id), '[]'),
    'by_branch', coalesce((select jsonb_agg(jsonb_build_object('branch_id', b.id, 'name', b.name_ar, 'grade', g.name_ar, 'count', c.n))
                            from public.academic_branches b join public.grades g on g.id = b.grade_id
                            join (select branch_id, count(*) n from public.student_academic_profiles where branch_id is not null group by branch_id) c
                              on c.branch_id = b.id), '[]'),
    'questions_total', (select count(*) from public.questions where deleted_at is null),
    'questions_live', (select count(*) from public.questions where deleted_at is null and public.is_live(status, publish_at, expires_at)),
    'files_live', (select count(*) from public.library_files where deleted_at is null and public.is_live(status, publish_at, expires_at)),
    'announcements_total', (select count(*) from public.announcements where deleted_at is null),
    'campaigns_total', (select count(*) from public.notification_campaigns),
    'recent_actions', coalesce((select jsonb_agg(x) from (
        select l.id, l.action, l.entity_type, l.entity_id, l.created_at, p.display_name as admin_name
        from public.admin_activity_logs l left join public.profiles p on p.id = l.admin_id
        order by l.created_at desc limit 15) x), '[]')
  ) into r;
  return r;
end $$;

-- Student list for administrators (no secrets, minimal personal data).
create or replace function public.admin_list_students(p_search text default null, p_grade uuid default null,
                                                      p_branch uuid default null, p_limit int default 50, p_offset int default 0)
returns table (id uuid, display_name text, email text, status public.account_status, grade_name text,
               branch_name text, governorate text, created_at timestamptz, last_seen_at timestamptz, total bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select p.id, p.display_name, p.email, p.status, g.name_ar, b.name_ar, s.governorate, p.created_at, p.last_seen_at,
         count(*) over ()
  from public.profiles p
  left join public.student_academic_profiles s on s.user_id = p.id
  left join public.grades g on g.id = s.grade_id
  left join public.academic_branches b on b.id = s.branch_id
  where not exists (select 1 from public.admin_roles a where a.user_id = p.id)
    and (p_search is null or p.display_name ilike '%' || p_search || '%' or p.email ilike '%' || p_search || '%')
    and (p_grade is null or s.grade_id = p_grade)
    and (p_branch is null or s.branch_id = p_branch)
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end $$;

create or replace function public.admin_set_student_status(p_user uuid, p_status public.account_status, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin_or_above() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if exists (select 1 from public.admin_roles where user_id = p_user) then
    raise exception 'cannot change an administrator account here';
  end if;
  update public.profiles set status = p_status,
         suspended_reason = case when p_status = 'suspended' then p_reason end
  where id = p_user;
  insert into public.admin_activity_logs (admin_id, action, entity_type, entity_id, after_data)
  values (auth.uid(), 'student_status:' || p_status, 'profiles', p_user::text, jsonb_build_object('reason', p_reason));
end $$;

-- Everything the student owns, as one JSON document (data export).
create or replace function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) - 'suspended_reason' from public.profiles p where id = uid),
    'academic_profile', (select to_jsonb(s) from public.student_academic_profiles s where user_id = uid),
    'preferences', (select to_jsonb(x) from public.user_preferences x where user_id = uid),
    'progress', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_subject_progress x where user_id = uid), '[]'),
    'schedules', coalesce((select jsonb_agg(to_jsonb(x)) from public.study_schedules x where user_id = uid), '[]'),
    'sessions', coalesce((select jsonb_agg(to_jsonb(x)) from public.study_sessions x where user_id = uid), '[]'),
    'tasks', coalesce((select jsonb_agg(to_jsonb(x)) from public.study_tasks x where user_id = uid), '[]'),
    'exams', coalesce((select jsonb_agg(to_jsonb(x)) from public.exams x where user_id = uid), '[]'),
    'notes', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_notes x where user_id = uid), '[]'),
    'goals', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_goals x where user_id = uid), '[]'),
    'achievements', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_achievements x where user_id = uid), '[]'),
    'expenses', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_expenses x where user_id = uid), '[]'),
    'study_logs', coalesce((select jsonb_agg(to_jsonb(x)) from public.study_logs x where user_id = uid), '[]'),
    'exam_attempts', coalesce((select jsonb_agg(to_jsonb(x)) from public.exam_attempts x where user_id = uid), '[]'),
    'answers', coalesce((select jsonb_agg(to_jsonb(x)) from public.student_answers x where user_id = uid), '[]'),
    'saved_questions', coalesce((select jsonb_agg(to_jsonb(x)) from public.saved_questions x where user_id = uid), '[]')
  );
end $$;

-- Marks the account for deletion; the delete-account Edge Function (service
-- role) removes the auth user, which cascades to every personal row.
create or replace function public.request_account_deletion() returns void
language sql security definer set search_path = public as $$
  update public.profiles set status = 'deletion_requested', deletion_requested_at = now() where id = auth.uid();
$$;

create or replace function public.touch_last_seen() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_seen_at = now() where id = auth.uid();
$$;

-- Record an announcement view / acknowledgment.
create or replace function public.mark_announcement_seen(p_id uuid, p_ack boolean default false) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.announcement_acknowledgments (announcement_id, user_id, acknowledged, acknowledged_at)
  values (p_id, auth.uid(), p_ack, case when p_ack then now() end)
  on conflict (announcement_id, user_id) do update
    set seen_count = announcement_acknowledgments.seen_count + 1,
        acknowledged = announcement_acknowledgments.acknowledged or excluded.acknowledged,
        acknowledged_at = coalesce(announcement_acknowledgments.acknowledged_at, excluded.acknowledged_at);
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled publishing. Visibility is already time-correct through is_live();
-- this job also rewrites the stored status so the dashboard shows the truth.
-- ---------------------------------------------------------------------------
create or replace function public.publish_due_content() returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; n_pub int := 0; n_exp int := 0; c int;
begin
  foreach t in array array['questions','library_files','daily_motivations','announcements','exams',
                           'universities','admission_information','app_versions'] loop
    execute format('update public.%I set status = ''published'' where status = ''scheduled'' and publish_at <= now()', t);
    get diagnostics c = row_count; n_pub := n_pub + c;
    execute format('update public.%I set status = ''expired'' where status = ''published'' and expires_at is not null and expires_at <= now()', t);
    get diagnostics c = row_count; n_exp := n_exp + c;
  end loop;
  return jsonb_build_object('published', n_pub, 'expired', n_exp);
end $$;
revoke execute on function public.publish_due_content() from authenticated, anon;

-- Run every minute when pg_cron is available (it is on Supabase; enable it in
-- Database -> Extensions). Notification dispatch is scheduled separately, see
-- docs/BACKEND_SETUP.md.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('enjaz-publish-due-content', '* * * * *', 'select public.publish_due_content()');
  end if;
exception when others then
  raise notice 'pg_cron not configured: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Storage buckets
-- ---------------------------------------------------------------------------
-- content: images for questions, motivation, announcements, covers (public read; paths are random uuids)
-- library: PDFs and study files (private; readable only when the file row is live and targets the student)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('content', 'content', true, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
       ('library', 'library', false, 104857600, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
       ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy storage_content_admin on storage.objects for all to authenticated
  using (bucket_id in ('content', 'library') and public.is_admin())
  with check (bucket_id in ('content', 'library') and public.is_admin());

create policy storage_library_read on storage.objects for select to authenticated
  using (bucket_id = 'library' and exists (
    select 1 from public.library_files f where f.storage_path = name));   -- filtered by library_files_read

create policy storage_avatar_own on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
