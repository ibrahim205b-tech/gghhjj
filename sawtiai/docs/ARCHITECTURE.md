# Architecture

## Overview

```
 Student app (Flutter)                      Admin dashboard (React)
 ├─ SQLite (offline source of truth)        └─ Supabase JS (anon key + admin session)
 ├─ Repository (ChangeNotifier) ─┐                    │
 ├─ Sync engine ─────────────────┼──── HTTPS ────► Supabase
 └─ Local notifications          │                 ├─ Postgres + RLS (authorization)
                                 │                 ├─ Auth (Google, anonymous, admin email)
          FCM ◄── send-notifications (Edge) ◄──────┤ Storage (content: public images, library: private files)
                                                   ├─ pg_cron: publish_due_content(), notification dispatch
                                                   └─ Edge Functions: send-notifications, delete-account
```

## Student app (apps/student)

- **Feature folders** under `lib/features/*`; **Riverpod** providers in `lib/app/providers.dart`;
  **GoRouter** with a 5-tab `StatefulShellRoute` in `lib/app/app.dart`.
- **Data**: `lib/data/local_db.dart` (sqflite tables `records`, `content`, `kv`, `downloads`) and
  `lib/data/repository.dart` (single source of truth, typed views in `models.dart`). Rows use the exact
  server column names, so no mapping layer is needed.
- **Sync** (`lib/services/backend.dart`):
  - Student-owned tables: push dirty rows (upsert by client-generated UUID), then pull rows whose
    `updated_at` is newer than the per-table cursor. Conflicts: `client_modified_at` last-write-wins,
    enforced on the server by a trigger (`reject_stale_write`) and on the client in `applyRemote`.
    Deletes are tombstones (`deleted_at`). Rows with a natural unique key (achievements, topic progress,
    saved questions) use deterministic UUID v5 ids so two devices never collide.
  - Published content: full refresh per table (RLS already limits it to the student's grade/branch), so
    unpublished or expired items disappear from the device.
  - Profiles created offline on the bundled structure are re-pointed to server ids by code after the first sync.
- **Logic** (pure, unit-tested): `logic/stats.dart`, `logic/planner.dart` (offline planner: urgency from
  exam dates × difficulty × flags × student priority; round-robin across subjects; respects daily capacity
  and exam deadlines; redistributes overdue tasks), `logic/quiz.dart` (Arabic-normalised answer checking),
  `logic/achievements.dart`.
- **Localization**: `lib/l10n/app_ar.arb` → generated `L10n` (Flutter gen-l10n). Every visible string goes
  through it.
- **Config**: `--dart-define` public values only (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `FIREBASE_*`).
  Missing values → the app runs fully offline and says so instead of faking sign-in.

## Database (supabase/migrations)

| File | Contents |
|---|---|
| `…01_core.sql` | enums, `profiles`, `admin_roles`, `is_admin()`, profile auto-creation, protected profile fields, append-only `admin_activity_logs` written by an audit trigger |
| `…02_academic.sql` | stages, grades, branches, years, subjects, chapters, topics, `student_academic_profiles` (+ consistency trigger), targeting helpers |
| `…03_student_data.sql` | all student-owned, sync-ready tables with last-write-wins triggers |
| `…04_content.sql` | questions/options/attempts/answers, library, motivation, announcements (+targets/acks), notification campaigns/recipients, universities/colleges/specializations/admission, app versions/settings |
| `…05_security.sql` | RLS for every table, grants, admin RPCs (`admin_overview`, `admin_list_students`, `admin_set_student_status`), `export_my_data`, `request_account_deletion`, `mark_announcement_seen`, `publish_due_content` + pg_cron job, storage buckets & policies |

Publication: `status` (draft/scheduled/published/expired/archived) + `publish_at` + `expires_at`.
Students see a row only when `is_live(...)` is true **at query time**, so scheduling is exact even if the
cron job is late; the job just rewrites the stored status for the dashboard.

Roles: `super_admin` > `admin` > `editor`. Students never read other students' data; admins do not read
students' personal study data either (only profile + academic profile via `admin_list_students`).
