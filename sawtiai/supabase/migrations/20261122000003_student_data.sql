-- Personal student data. Designed for offline-first sync:
--   * ids are generated on the device (uuid v4),
--   * deletes are soft (deleted_at tombstones) so other devices learn about them,
--   * updated_at is the server-side pull cursor (set by trigger),
--   * client_modified_at resolves conflicts: an older write never overwrites a newer one.

create type public.topic_status as enum ('not_started', 'in_progress', 'completed', 'needs_revision');

create or replace function public.reject_stale_write() returns trigger
language plpgsql as $$
begin
  if new.client_modified_at < old.client_modified_at then
    return old;            -- keep the newer server copy (last-write-wins)
  end if;
  new.updated_at := now();
  return new;
end $$;

create table public.student_subject_progress (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  topic_id           uuid not null references public.topics (id) on delete cascade,
  status             public.topic_status not null default 'not_started',
  is_difficult       boolean not null default false,
  revision_count     int not null default 0,
  note               text check (char_length(note) <= 4000),
  completed_at       timestamptz,
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (user_id, topic_id)
);

create table public.study_schedules (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title              text not null check (char_length(title) <= 120),
  is_active          boolean not null default true,
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.study_sessions (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  schedule_id        uuid references public.study_schedules (id) on delete cascade,
  subject_id         uuid references public.subjects (id) on delete set null,
  custom_subject     text check (char_length(custom_subject) <= 80),
  title              text check (char_length(title) <= 120),
  weekday            smallint check (weekday between 1 and 7),       -- for repeating sessions (ISO, 1=Mon)
  session_date       date,                                            -- for one-off sessions
  start_time         time not null,
  end_time           time not null,
  break_minutes      smallint not null default 0 check (break_minutes between 0 and 240),
  repeats_weekly     boolean not null default false,
  note               text check (char_length(note) <= 2000),
  completed_dates    date[] not null default '{}',
  actual_minutes     int not null default 0 check (actual_minutes >= 0),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (end_time > start_time),
  check (repeats_weekly = (weekday is not null)),
  check (repeats_weekly or session_date is not null)
);
create index study_sessions_user_idx on public.study_sessions (user_id, updated_at);

create table public.study_tasks (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title              text not null check (char_length(title) <= 200),
  subject_id         uuid references public.subjects (id) on delete set null,
  topic_id           uuid references public.topics (id) on delete set null,
  due_date           date,
  start_time         time,
  end_time           time,
  estimated_minutes  int check (estimated_minutes between 0 and 1440),
  priority           smallint not null default 2 check (priority between 1 and 3),   -- 1 low, 2 normal, 3 high
  is_done            boolean not null default false,
  done_at            timestamptz,
  source             text not null default 'manual' check (source in ('manual', 'planner')),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index study_tasks_user_idx on public.study_tasks (user_id, updated_at);

-- Exams: official dates (admin, is_official) and personal reminders (student).
create table public.exams (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users (id) on delete cascade,  -- null for official exams
  is_official        boolean not null default false,
  title              text not null check (char_length(title) <= 200),
  subject_id         uuid references public.subjects (id) on delete set null,
  grade_id           uuid references public.grades (id) on delete cascade,
  branch_id          uuid references public.academic_branches (id) on delete cascade,
  exam_at            timestamptz not null,
  location           text,
  source_url         text,
  verified_at        timestamptz,
  score              numeric(6,2),
  max_score          numeric(6,2) check (max_score is null or max_score > 0),
  target_score       numeric(6,2),
  note               text check (char_length(note) <= 2000),
  status             public.publication_status not null default 'published',
  publish_at         timestamptz,
  expires_at         timestamptz,
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (is_official = (user_id is null))
);
create index exams_user_idx on public.exams (user_id, updated_at);
create index exams_official_idx on public.exams (is_official, grade_id, exam_at);

create table public.student_notes (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title              text check (char_length(title) <= 200),
  body               text not null default '' check (char_length(body) <= 20000),
  subject_id         uuid references public.subjects (id) on delete set null,
  is_pinned          boolean not null default false,
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.student_goals (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  period             text not null check (period in ('weekly', 'monthly')),
  title              text not null check (char_length(title) <= 200),
  target_value       numeric not null default 1 check (target_value > 0),
  current_value      numeric not null default 0,
  unit               text not null default 'count' check (unit in ('count', 'hours', 'topics', 'tasks')),
  starts_on          date not null,
  ends_on            date not null,
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table public.student_achievements (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  code               text not null,                -- streak_7, tasks_100, ...
  earned_at          timestamptz not null default now(),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (user_id, code)
);

create table public.student_expenses (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title              text not null check (char_length(title) <= 120),
  amount_iqd         numeric(14,0) not null check (amount_iqd >= 0),
  category           text not null default 'other',
  spent_on           date not null,
  note               text check (char_length(note) <= 1000),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Daily studied minutes (from timers / completed sessions) for stats & streaks.
create table public.study_logs (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  log_date           date not null,
  subject_id         uuid references public.subjects (id) on delete set null,
  minutes            int not null check (minutes between 1 and 1440),
  source             text not null default 'timer' check (source in ('timer', 'pomodoro', 'session', 'manual')),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index study_logs_user_date_idx on public.study_logs (user_id, log_date);

create table public.user_preferences (
  user_id              uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  notify_motivation    boolean not null default true,
  notify_study         boolean not null default true,
  notify_exams         boolean not null default true,
  notify_announcements boolean not null default true,
  theme_mode           text not null default 'dark' check (theme_mode in ('dark', 'light', 'system')),
  daily_study_hours    numeric(4,1) not null default 3 check (daily_study_hours between 0 and 18),
  cloud_sync_enabled   boolean not null default true,
  client_modified_at   timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create table public.device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  token        text not null unique,
  platform     text not null default 'android',
  app_version  text,
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.sync_metadata (
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  device_id      text not null,
  last_pulled_at timestamptz,
  last_pushed_at timestamptz,
  app_version    text,
  updated_at     timestamptz not null default now(),
  primary key (user_id, device_id)
);

do $$
declare t text;
begin
  foreach t in array array['student_subject_progress','study_schedules','study_sessions','study_tasks',
                           'student_notes','student_goals','student_achievements','student_expenses',
                           'study_logs','user_preferences'] loop
    execute format('create trigger %1$s_lww before update on public.%1$s
                    for each row execute function public.reject_stale_write()', t);
  end loop;
end $$;
create trigger exams_updated_at before update on public.exams
  for each row execute function public.set_updated_at();
create trigger sync_metadata_updated_at before update on public.sync_metadata
  for each row execute function public.set_updated_at();
