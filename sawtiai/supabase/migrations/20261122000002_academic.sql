-- Academic structure. Everything is admin-editable; nothing here is
-- hardcoded in the apps. Soft deletion via deleted_at.

create table public.academic_stages (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,                -- e.g. intermediate, preparatory
  name_ar    text not null,
  name_en    text not null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.grades (
  id          uuid primary key default gen_random_uuid(),
  stage_id    uuid not null references public.academic_stages (id) on delete restrict,
  code        text not null unique,               -- e.g. grade_7 ... grade_12
  name_ar     text not null,
  name_en     text not null,
  has_branches boolean not null default false,
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index grades_stage_idx on public.grades (stage_id);

create table public.academic_branches (
  id         uuid primary key default gen_random_uuid(),
  grade_id   uuid not null references public.grades (id) on delete restrict,
  code       text not null,                       -- scientific, literary, applied, biological
  name_ar    text not null,
  name_en    text not null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (grade_id, code)
);

create table public.academic_years (
  id         uuid primary key default gen_random_uuid(),
  label      text not null unique,                -- 2026-2027
  starts_on  date,
  ends_on    date,
  is_current boolean not null default false,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index academic_years_one_current on public.academic_years (is_current) where is_current and deleted_at is null;

create table public.subjects (
  id          uuid primary key default gen_random_uuid(),
  grade_id    uuid not null references public.grades (id) on delete restrict,
  branch_id   uuid references public.academic_branches (id) on delete restrict, -- null = all branches of the grade
  year_id     uuid references public.academic_years (id) on delete restrict,   -- null = every year
  name_ar     text not null,
  name_en     text,
  icon        text not null default 'book',
  color       text not null default '#3DA9FC' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  is_verified boolean not null default false,     -- confirmed against the official curriculum
  source_note text,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index subjects_grade_branch_idx on public.subjects (grade_id, branch_id);

create table public.chapters (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects (id) on delete cascade,
  title      text not null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index chapters_subject_idx on public.chapters (subject_id);

create table public.topics (
  id         uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.chapters (id) on delete cascade,
  title      text not null,
  difficulty smallint not null default 2 check (difficulty between 1 and 3),
  sort_order int not null default 0,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index topics_chapter_idx on public.topics (chapter_id);

-- Student's chosen academic profile.
create table public.student_academic_profiles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  stage_id    uuid not null references public.academic_stages (id),
  grade_id    uuid not null references public.grades (id),
  branch_id   uuid references public.academic_branches (id),
  year_id     uuid references public.academic_years (id),
  governorate text check (governorate is null or char_length(governorate) <= 40),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index sap_grade_branch_idx on public.student_academic_profiles (grade_id, branch_id);

-- Branch must belong to the grade, grade to the stage, and a branch is
-- required exactly when the grade has branches.
create or replace function public.validate_academic_profile() returns trigger
language plpgsql as $$
declare v_has_branches boolean; v_stage uuid;
begin
  select has_branches, stage_id into v_has_branches, v_stage from public.grades where id = new.grade_id;
  if v_stage is distinct from new.stage_id then
    raise exception 'grade does not belong to stage';
  end if;
  if v_has_branches and new.branch_id is null then
    raise exception 'branch is required for this grade';
  end if;
  if not v_has_branches and new.branch_id is not null then
    raise exception 'this grade has no branches';
  end if;
  if new.branch_id is not null and not exists
     (select 1 from public.academic_branches where id = new.branch_id and grade_id = new.grade_id) then
    raise exception 'branch does not belong to grade';
  end if;
  return new;
end $$;
create trigger sap_validate before insert or update on public.student_academic_profiles
  for each row execute function public.validate_academic_profile();

create or replace function public.my_grade_id() returns uuid
language sql stable security definer set search_path = public as $$
  select grade_id from public.student_academic_profiles where user_id = auth.uid()
$$;
create or replace function public.my_branch_id() returns uuid
language sql stable security definer set search_path = public as $$
  select branch_id from public.student_academic_profiles where user_id = auth.uid()
$$;
create or replace function public.my_stage_id() returns uuid
language sql stable security definer set search_path = public as $$
  select stage_id from public.student_academic_profiles where user_id = auth.uid()
$$;

-- Does content targeted at (grade, branch) apply to the current student?
-- null grade/branch on the content means "all".
create or replace function public.targets_me(p_grade uuid, p_branch uuid) returns boolean
language sql stable as $$
  select (p_grade is null or p_grade = public.my_grade_id())
     and (p_branch is null or p_branch = public.my_branch_id())
$$;

-- Array-targeted content (empty / null array = everyone).
create or replace function public.targets_me_arrays(p_grades uuid[], p_branches uuid[], p_stages uuid[]) returns boolean
language sql stable as $$
  select (coalesce(cardinality(p_stages), 0) = 0 or public.my_stage_id() = any (p_stages))
     and (coalesce(cardinality(p_grades), 0) = 0 or public.my_grade_id() = any (p_grades))
     and (coalesce(cardinality(p_branches), 0) = 0 or public.my_branch_id() = any (p_branches))
$$;

do $$
declare t text;
begin
  foreach t in array array['academic_stages','grades','academic_branches','academic_years','subjects',
                           'chapters','topics','student_academic_profiles'] loop
    execute format('create trigger %1$s_updated_at before update on public.%1$s
                    for each row execute function public.set_updated_at()', t);
  end loop;
  foreach t in array array['academic_stages','grades','academic_branches','academic_years','subjects',
                           'chapters','topics'] loop
    perform public.enable_audit(('public.' || t)::regclass);
  end loop;
end $$;
