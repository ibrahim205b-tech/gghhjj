-- Admin-managed content: question bank, library, motivation, announcements,
-- notifications, guidance, app versions & settings.
-- Every publishable row has status / publish_at / expires_at; students only
-- ever see rows where public.is_live(...) is true (enforced by RLS).

-- ---------------------------------------------------------------------------
-- Question bank
-- ---------------------------------------------------------------------------
create type public.question_type as enum ('multiple_choice', 'true_false', 'short_answer');

create table public.questions (
  id            uuid primary key default gen_random_uuid(),
  grade_id      uuid not null references public.grades (id) on delete restrict,
  branch_id     uuid references public.academic_branches (id) on delete restrict,
  year_id       uuid references public.academic_years (id) on delete set null,
  subject_id    uuid not null references public.subjects (id) on delete restrict,
  chapter_id    uuid references public.chapters (id) on delete set null,
  topic_id      uuid references public.topics (id) on delete set null,
  question_type public.question_type not null,
  question_text text not null check (char_length(question_text) between 1 and 5000),
  image_path    text,                       -- storage path in bucket "content"
  answer_text   text,                       -- accepted answer for short_answer (normalised compare)
  explanation   text check (char_length(explanation) <= 5000),
  difficulty    smallint not null default 2 check (difficulty between 1 and 3),
  source        text,                       -- e.g. "ministerial exam 2023 round 1" - must be truthful
  source_type   text not null default 'practice' check (source_type in ('official_ministerial', 'textbook', 'practice', 'teacher')),
  question_year int check (question_year between 1990 and 2100),
  status        public.publication_status not null default 'draft',
  publish_at    timestamptz,
  expires_at    timestamptz,
  created_by    uuid references auth.users (id) on delete set null,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (question_type <> 'short_answer' or answer_text is not null)
);
create index questions_lookup_idx on public.questions (grade_id, subject_id, chapter_id, topic_id) where deleted_at is null;
create index questions_status_idx on public.questions (status, publish_at);

create table public.question_options (
  id          uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions (id) on delete cascade,
  option_text text not null check (char_length(option_text) between 1 and 1000),
  is_correct  boolean not null default false,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index question_options_q_idx on public.question_options (question_id);

-- Practice test attempts (question bank)
create table public.exam_attempts (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  subject_id         uuid references public.subjects (id) on delete set null,
  chapter_id         uuid references public.chapters (id) on delete set null,
  topic_id           uuid references public.topics (id) on delete set null,
  mode               text not null default 'untimed' check (mode in ('timed', 'untimed', 'review_mistakes')),
  time_limit_seconds int,
  started_at         timestamptz not null,
  finished_at        timestamptz,
  total_questions    int not null default 0,
  correct_count      int not null default 0,
  score_percent      numeric(5,2),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index exam_attempts_user_idx on public.exam_attempts (user_id, updated_at);

create table public.student_answers (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  attempt_id         uuid not null references public.exam_attempts (id) on delete cascade,
  question_id        uuid not null references public.questions (id) on delete cascade,
  selected_option_id uuid references public.question_options (id) on delete set null,
  text_answer        text check (char_length(text_answer) <= 2000),
  is_correct         boolean not null default false,
  answered_at        timestamptz not null default now(),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (attempt_id, question_id)
);
create index student_answers_user_idx on public.student_answers (user_id, updated_at);

create table public.saved_questions (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  question_id        uuid not null references public.questions (id) on delete cascade,
  reason             text not null default 'difficult' check (reason in ('difficult', 'wrong', 'favorite')),
  client_modified_at timestamptz not null default now(),
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (user_id, question_id)
);

-- ---------------------------------------------------------------------------
-- Library
-- ---------------------------------------------------------------------------
create table public.library_categories (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,          -- books, notes, summaries, worksheets, images, supplementary
  name_ar    text not null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.library_files (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.library_categories (id) on delete set null,
  stage_id     uuid references public.academic_stages (id) on delete set null,
  grade_id     uuid references public.grades (id) on delete restrict,
  branch_id    uuid references public.academic_branches (id) on delete restrict,
  subject_id   uuid references public.subjects (id) on delete set null,
  chapter_id   uuid references public.chapters (id) on delete set null,
  title        text not null check (char_length(title) between 1 and 200),
  description  text check (char_length(description) <= 4000),
  storage_path text not null,               -- bucket "library"
  cover_path   text,                        -- bucket "content"
  mime_type    text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  size_bytes   bigint not null check (size_bytes > 0 and size_bytes <= 104857600),
  page_count   int,
  source       text,
  download_count int not null default 0,
  status       public.publication_status not null default 'draft',
  publish_at   timestamptz,
  expires_at   timestamptz,
  created_by   uuid references auth.users (id) on delete set null,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index library_files_lookup_idx on public.library_files (grade_id, branch_id, subject_id) where deleted_at is null;

create table public.file_downloads (
  id         uuid primary key default gen_random_uuid(),
  file_id    uuid not null references public.library_files (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index file_downloads_file_idx on public.file_downloads (file_id);

create or replace function public.bump_download_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.library_files set download_count = download_count + 1 where id = new.file_id;
  return new;
end $$;
create trigger file_downloads_count after insert on public.file_downloads
  for each row execute function public.bump_download_count();

-- ---------------------------------------------------------------------------
-- Daily motivation
-- ---------------------------------------------------------------------------
create table public.daily_motivations (
  id               uuid primary key default gen_random_uuid(),
  title            text check (char_length(title) <= 200),
  body             text not null check (char_length(body) between 1 and 2000),
  image_path       text,
  author           text check (char_length(author) <= 120),
  author_verified  boolean not null default false,
  target_stage_ids  uuid[] not null default '{}',
  target_grade_ids  uuid[] not null default '{}',
  target_branch_ids uuid[] not null default '{}',
  show_on          date,                    -- optional: the day this card is "today's motivation"
  status           public.publication_status not null default 'draft',
  publish_at       timestamptz,
  expires_at       timestamptz,
  created_by       uuid references auth.users (id) on delete set null,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Announcements (image popups / screens)
-- ---------------------------------------------------------------------------
create type public.display_frequency as enum ('once', 'until_acknowledged', 'every_launch');

create table public.announcements (
  id                    uuid primary key default gen_random_uuid(),
  kind                  text not null default 'general' check (kind in ('general', 'content', 'exam_schedule', 'notice', 'telegram', 'app_update')),
  title                 text not null check (char_length(title) between 1 and 200),
  description           text check (char_length(description) <= 4000),
  image_path            text,
  action_label          text check (char_length(action_label) <= 60),
  action_url            text check (action_url is null or action_url ~ '^(https://|enjaz://)'),
  telegram_url          text check (telegram_url is null or telegram_url ~ '^https://(t\.me|telegram\.me)/'),
  priority              int not null default 0,
  display_frequency     public.display_frequency not null default 'once',
  requires_acknowledgment boolean not null default false,
  target_all            boolean not null default true,
  status                public.publication_status not null default 'draft',
  publish_at            timestamptz,
  expires_at            timestamptz,
  created_by            uuid references auth.users (id) on delete set null,
  deleted_at            timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table public.announcement_targets (
  id              uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  stage_id        uuid references public.academic_stages (id) on delete cascade,
  grade_id        uuid references public.grades (id) on delete cascade,
  branch_id       uuid references public.academic_branches (id) on delete cascade,
  check (stage_id is not null or grade_id is not null or branch_id is not null)
);
create index announcement_targets_ann_idx on public.announcement_targets (announcement_id);

create table public.announcement_acknowledgments (
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  seen_count      int not null default 1,
  acknowledged    boolean not null default false,
  first_seen_at   timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key (announcement_id, user_id)
);

create or replace function public.announcement_targets_me(p_id uuid, p_target_all boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select p_target_all or exists (
    select 1 from public.announcement_targets t
    where t.announcement_id = p_id
      and (t.stage_id is null or t.stage_id = public.my_stage_id())
      and (t.grade_id is null or t.grade_id = public.my_grade_id())
      and (t.branch_id is null or t.branch_id = public.my_branch_id()))
$$;

-- ---------------------------------------------------------------------------
-- Push notification campaigns (sent by the send-notifications Edge Function)
-- ---------------------------------------------------------------------------
create type public.campaign_status as enum ('draft', 'scheduled', 'sending', 'sent', 'failed', 'cancelled');

create table public.notification_campaigns (
  id                uuid primary key default gen_random_uuid(),
  title             text not null check (char_length(title) between 1 and 120),
  body              text not null check (char_length(body) between 1 and 500),
  image_url         text check (image_url is null or image_url ~ '^https://'),
  deep_link         text check (deep_link is null or deep_link ~ '^enjaz://'),
  audience          text not null default 'all' check (audience in ('all', 'stage', 'grade', 'branch', 'user')),
  target_stage_ids  uuid[] not null default '{}',
  target_grade_ids  uuid[] not null default '{}',
  target_branch_ids uuid[] not null default '{}',
  target_user_id    uuid references auth.users (id) on delete cascade,
  category          text not null default 'announcements' check (category in ('announcements', 'motivation', 'study', 'exams')),
  status            public.campaign_status not null default 'draft',
  scheduled_at      timestamptz,
  sent_at           timestamptz,
  total_recipients  int not null default 0,
  success_count     int not null default 0,
  failure_count     int not null default 0,
  last_error        text,
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (audience <> 'user' or target_user_id is not null)
);
create index notification_campaigns_due_idx on public.notification_campaigns (status, scheduled_at);

create table public.notification_recipients (
  id          uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.notification_campaigns (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  token_id    uuid references public.device_tokens (id) on delete set null,
  delivered   boolean not null default false,
  error       text,
  created_at  timestamptz not null default now()
);
create index notification_recipients_campaign_idx on public.notification_recipients (campaign_id);

-- ---------------------------------------------------------------------------
-- University & future guidance
-- ---------------------------------------------------------------------------
create table public.universities (
  id           uuid primary key default gen_random_uuid(),
  name_ar      text not null,
  name_en      text,
  governorate  text,
  kind         text not null default 'public' check (kind in ('public', 'private', 'institute')),
  website      text,
  description  text,
  status       public.publication_status not null default 'draft',
  publish_at   timestamptz,
  expires_at   timestamptz,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.colleges (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities (id) on delete cascade,
  name_ar       text not null,
  description   text,
  sort_order    int not null default 0,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.specializations (
  id          uuid primary key default gen_random_uuid(),
  college_id  uuid not null references public.colleges (id) on delete cascade,
  name_ar     text not null,
  description text,
  study_years smallint,
  branch_codes text[] not null default '{}',   -- which preparatory branches may apply
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.admission_information (
  id                 uuid primary key default gen_random_uuid(),
  specialization_id  uuid references public.specializations (id) on delete cascade,
  college_id         uuid references public.colleges (id) on delete cascade,
  academic_year_label text not null,
  admission_channel  text not null default 'central' check (admission_channel in ('central', 'parallel', 'evening', 'private', 'scholarship', 'other')),
  min_average        numeric(5,2) check (min_average between 0 and 100),
  application_deadline date,
  details            text,
  source_name        text not null,                 -- mandatory: where this came from
  source_url         text,
  is_official        boolean not null default false, -- only true when verified from an official source
  verified_at        timestamptz,
  status             public.publication_status not null default 'draft',
  publish_at         timestamptz,
  expires_at         timestamptz,
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (specialization_id is not null or college_id is not null),
  check (not is_official or verified_at is not null)
);

-- ---------------------------------------------------------------------------
-- App versions & settings
-- ---------------------------------------------------------------------------
create table public.app_versions (
  id                    uuid primary key default gen_random_uuid(),
  version_name          text not null,                 -- 1.2.0
  build_number          int not null unique check (build_number > 0),
  release_date          date not null default current_date,
  description           text,
  image_path            text,
  download_url          text check (download_url is null or download_url ~ '^https://'),
  play_store_url        text check (play_store_url is null or play_store_url ~ '^https://play\.google\.com/'),
  telegram_url          text check (telegram_url is null or telegram_url ~ '^https://(t\.me|telegram\.me)/'),
  min_supported_build   int not null default 1,
  is_mandatory          boolean not null default false,
  status                public.publication_status not null default 'draft',
  publish_at            timestamptz,
  expires_at            timestamptz,
  created_by            uuid references auth.users (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (download_url is not null or play_store_url is not null or telegram_url is not null)
);

create table public.app_settings (
  key        text primary key check (key ~ '^[a-z0-9_.]+$'),
  value      jsonb not null,
  is_public  boolean not null default true,   -- readable by students
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['questions','question_options','library_categories','library_files',
                           'daily_motivations','announcements','notification_campaigns','universities',
                           'colleges','specializations','admission_information','app_versions','app_settings'] loop
    execute format('create trigger %1$s_updated_at before update on public.%1$s
                    for each row execute function public.set_updated_at()', t);
  end loop;
  foreach t in array array['exam_attempts','student_answers','saved_questions'] loop
    execute format('create trigger %1$s_lww before update on public.%1$s
                    for each row execute function public.reject_stale_write()', t);
  end loop;
  foreach t in array array['questions','question_options','library_categories','library_files',
                           'daily_motivations','announcements','announcement_targets','notification_campaigns',
                           'universities','colleges','specializations','admission_information',
                           'app_versions','app_settings','exams'] loop
    perform public.enable_audit(('public.' || t)::regclass);
  end loop;
end $$;
