-- ENJAZ core: extensions, enums, helpers, profiles, admin roles, audit log.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.publication_status as enum ('draft', 'scheduled', 'published', 'expired', 'archived');
create type public.account_status as enum ('active', 'suspended', 'deletion_requested');
create type public.admin_role as enum ('super_admin', 'admin', 'editor');

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- True when published content should be visible right now.
create or replace function public.is_live(p_status public.publication_status,
                                          p_publish_at timestamptz,
                                          p_expires_at timestamptz)
returns boolean language sql immutable as $$
  select case
    when p_status = 'published' then (p_expires_at is null or p_expires_at > now())
    when p_status = 'scheduled' then p_publish_at is not null and p_publish_at <= now()
                                     and (p_expires_at is null or p_expires_at > now())
    else false
  end
$$;
-- now() is stable, not immutable; declare correctly.
alter function public.is_live(public.publication_status, timestamptz, timestamptz) stable;

-- ---------------------------------------------------------------------------
-- Profiles (one per auth user)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default '' check (char_length(display_name) <= 80),
  avatar_url    text,
  email         text,
  status        public.account_status not null default 'active',
  suspended_reason text,
  deletion_requested_at timestamptz,
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Administrators. There is NO self-registration: rows are inserted by a
-- super_admin or once via the SQL editor (see docs/ADMIN_SETUP.md).
-- ---------------------------------------------------------------------------
create table public.admin_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       public.admin_role not null default 'editor',
  granted_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_roles where user_id = auth.uid())
$$;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_roles where user_id = auth.uid() and role = 'super_admin')
$$;

-- Active (not suspended) student or any admin.
create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.is_admin() or exists (select 1 from public.profiles
                                 where id = auth.uid() and status <> 'suspended'))
$$;

-- New auth user -> profile (Google name / picture taken from metadata).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, avatar_url, email)
  values (new.id,
          left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 80),
          new.raw_user_meta_data ->> 'avatar_url',
          new.email)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Students may not change their own moderation fields.
create or replace function public.protect_profile_fields() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and auth.uid() is not null then
    if new.status is distinct from old.status
       and not (old.status = 'active' and new.status = 'deletion_requested') then
      raise exception 'not allowed to change account status';
    end if;
    if new.suspended_reason is distinct from old.suspended_reason or new.email is distinct from old.email then
      raise exception 'not allowed to change protected profile fields';
    end if;
  end if;
  return new;
end $$;
create trigger profiles_protect before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- ---------------------------------------------------------------------------
-- Administrative activity log (append-only; written by triggers only)
-- ---------------------------------------------------------------------------
create table public.admin_activity_logs (
  id          uuid primary key default gen_random_uuid(),
  admin_id    uuid references auth.users (id) on delete set null,
  action      text not null,                 -- insert | update | delete | publish | send | suspend ...
  entity_type text not null,                 -- table name
  entity_id   text,
  before_data jsonb,
  after_data  jsonb,
  created_at  timestamptz not null default now()
);
create index admin_activity_logs_created_idx on public.admin_activity_logs (created_at desc);
create index admin_activity_logs_entity_idx on public.admin_activity_logs (entity_type, entity_id);

create or replace function public.log_admin_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_action text := lower(tg_op);
  v_id text;
  v_before jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_after  jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
begin
  if not public.is_admin() then
    return coalesce(new, old);
  end if;
  v_id := coalesce(v_after ->> 'id', v_before ->> 'id', v_after ->> 'user_id', v_before ->> 'user_id');
  if tg_op = 'UPDATE' and (v_before ->> 'status') is distinct from (v_after ->> 'status') then
    v_action := 'status:' || coalesce(v_after ->> 'status', '');
  end if;
  -- Never copy large or sensitive blobs into the log.
  v_before := v_before - 'answer_text';
  v_after  := v_after - 'answer_text';
  insert into public.admin_activity_logs (admin_id, action, entity_type, entity_id, before_data, after_data)
  values (auth.uid(), v_action, tg_table_name, v_id, v_before, v_after);
  return coalesce(new, old);
end $$;

-- Helper to attach the audit trigger to a table.
create or replace function public.enable_audit(p_table regclass) returns void
language plpgsql as $$
begin
  execute format('create trigger audit_%s after insert or update or delete on %s
                  for each row execute function public.log_admin_change()',
                 replace(p_table::text, 'public.', ''), p_table);
end $$;

select public.enable_audit('public.admin_roles');
select public.enable_audit('public.profiles');
