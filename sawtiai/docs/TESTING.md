# Testing

All results below come from real runs (locally and on GitHub Actions). Nothing is simulated except where a
test explicitly says it uses a scripted fixture.

## Summary

| Layer | Where | Tests | Result |
|---|---|---|---|
| Database security (RLS) & behaviour | `supabase/tests/rls_test.sql` on PostgreSQL 16 | 1 script, ~40 assertions | ✅ pass (local + CI) |
| Real Supabase stack end-to-end | `supabase/tests/e2e.mjs` on `supabase start` (Auth, PostgREST, Storage, Edge Functions) | 16 checks | ✅ pass ([run](https://github.com/ibrahim205b-tech/gghhjj/actions/runs/44985774968)) |
| Student app logic | `apps/student/test/logic_test.dart` | 15 | ✅ pass |
| Student app repository / offline store (real SQLite) | `apps/student/test/repository_test.dart` | 9 | ✅ pass |
| Student app UI flows (widget tests) | `apps/student/test/widget_flow_test.dart` | 6 | ✅ pass |
| Admin dashboard | `apps/admin/src/admin.test.tsx` (Vitest) | 8 | ✅ pass |
| Static analysis | `flutter analyze --fatal-infos`, `tsc -b` | — | ✅ 0 issues |
| APK build + verification | `enjaz-student.yml` (aapt2 badging: package, label; apksigner) | — | ✅ `ENJAZ.apk` built |

## What is covered

### Database (rls_test.sql)
- Profile auto-created from Google metadata; branch required for preparatory grades; grade/branch consistency.
- Students see only **live** content of **their own grade/branch**: drafts, future-scheduled and expired
  questions are hidden; past-scheduled ones are visible; options of hidden questions are hidden.
- Announcements/motivation targeting by grade; acknowledgments recorded.
- Students cannot: insert questions, grant themselves admin, call admin RPCs, change moderation fields,
  create "official" exams, read other students' tasks/exams, read activity logs.
- Last-write-wins: an older device write does not overwrite a newer one.
- Suspending a student blocks their writes; `admin_overview`/`admin_list_students` work for admins only.
- Every admin change is written to the append-only activity log.
- `publish_due_content()` flips scheduled→published and published→expired correctly.
- Deleting the auth user deletes all personal data (cascade).

### Real stack (e2e.mjs)
Admin provisioned with the service role → logs in by email → creates subject/chapter/questions/
announcement/app version → uploads a PDF to the private bucket → activity logged. Anonymous student →
sets grade 12 applied → sees only the published question → downloads the PDF through a signed URL →
cannot write content / escalate / call admin RPCs → sync upserts with LWW → device token, acknowledgment,
data export → isolation between students → admin lists, suspends (writes blocked) and restores →
**send-notifications Edge Function**: students are refused; for the admin it runs and, without Firebase
credentials, marks the campaign `failed: fcm_not_configured` (it never pretends) → **delete-account**
removes the user and all data.

### Student app
- Onboarding offline end-to-end (RTL, Iraqi strings), honest "backend not configured" message.
- Home statistics from real data (0/0 when empty, updates when a task is added/completed).
- Subjects never mixed across grades/branches; topic status drives completion %.
- Full quiz: start → answer → submit → real score → answers stored.
- Schedule: weekly session → mark done → a real study log (60 min) is created.
- Settings: light theme applies and persists.
- Offline persistence across a simulated restart; tombstone deletes; offline→server id reconciliation;
  deterministic UUIDs; export; wipe.
- Planner: capacity, exam urgency/deadline, existing load, redistribution; Arabic short-answer normalisation.

## Not covered / limitations (honest list)

- **On-device test** on a physical phone or emulator (camera/notifications/OAuth browser round-trip) was not
  run: there is no Supabase project or Firebase project connected yet, so Google sign-in, real push delivery
  and cloud sync against a hosted backend could not be exercised. The local real-stack e2e covers the same
  APIs except Google OAuth and FCM delivery.
- Google sign-in requires the owner's Google Cloud OAuth client (see BACKEND_SETUP §4).
- Push delivery requires the owner's Firebase service account (BACKEND_SETUP §5).
- The admin dashboard UI was tested with unit tests and a production build; it has not been clicked through
  against a hosted project.

## How to run

```bash
# database (needs PostgreSQL 16)
psql -c "create database enjaz" && psql -d enjaz -f supabase/tests/local_supabase_stub.sql
for f in supabase/migrations/*.sql supabase/seed.sql; do psql -d enjaz -f $f; done
psql -d enjaz -f supabase/tests/rls_test.sql

# real stack (Docker)
supabase start && eval "$(supabase status -o env)" && \
  SUPABASE_URL=$API_URL ANON_KEY=$ANON_KEY SERVICE_KEY=$SERVICE_ROLE_KEY node supabase/tests/e2e.mjs

cd apps/student && flutter test
cd apps/admin && npm test
```

## CI
- `ENJAZ — Student app (APK)`: analyze → tests → release APK → verify → artifact.
- `ENJAZ — Admin dashboard`: typecheck → tests → build → artifact.
- `ENJAZ — Database & backend`: migrations + RLS tests on PostgreSQL 16, then the real-stack e2e.
