# Backend setup (Supabase + Google sign-in + Firebase)

Everything here uses **free tiers that need no credit card** (Supabase Free, Google Cloud OAuth consent
screen in "Testing"/"In production" without billing, Firebase Spark). Limits are listed at the end.

The apps work **without** any of this (offline mode). These steps turn on accounts, cloud sync, published
content, the admin dashboard and push notifications.

---

## 1. Create the Supabase project

1. Sign up at <https://supabase.com> → **New project** (region close to Iraq, e.g. Frankfurt).
2. Keep the database password somewhere safe (never in git).
3. **Project Settings → API**: copy the **Project URL** and the **anon / publishable key**.
   These two are *public* client values. **Never** copy the `service_role` key into any app or file.

## 2. Apply the database

Option 0 — GitHub Actions, no local tools (easiest):

1. GitHub → **Settings → Secrets and variables → Actions**.
2. **Secrets**: `SUPABASE_ACCESS_TOKEN` (supabase.com → Account → Access Tokens) and
   `SUPABASE_DB_PASSWORD` (the database password chosen when the project was created).
3. **Variables**: `ENJAZ_SUPABASE_URL` (`https://<ref>.supabase.co`) and `ENJAZ_SUPABASE_ANON_KEY`
   (Project Settings → API → anon / publishable key — public by design, protected by RLS).
4. **Actions → «ENJAZ — Deploy backend to Supabase» → Run workflow.** It applies the migrations and seed,
   deploys both Edge Functions, pushes the auth settings (anonymous sign-in, redirect URLs) and checks the
   live API.

Option A — Supabase CLI:

```bash
cd sawtiai
supabase login
supabase link --project-ref <your-project-ref>
supabase db push              # applies supabase/migrations/*
psql "$(supabase db url)" -f supabase/seed.sql   # stages/grades/branches/years/categories (once)
supabase functions deploy send-notifications --no-verify-jwt
supabase functions deploy delete-account
```

Option B — dashboard: paste each file of `supabase/migrations/` in order into **SQL Editor → Run**,
then `supabase/seed.sql`, and deploy the two functions from **Edge Functions**.

Then: **Database → Extensions** → enable **pg_cron** and **pg_net** (needed for scheduled publishing and
scheduled notifications). If pg_cron was enabled *after* the migrations ran, run once in SQL Editor:

```sql
select cron.schedule('enjaz-publish-due-content', '* * * * *', 'select public.publish_due_content()');
```

> The seeded academic structure (Intermediate 1–3, Preparatory 4–6 with Scientific/Literary and
> Applied/Biological branches) is flagged **needs verification** (`app_settings.academic_structure_verified = false`).
> No subjects, chapters, questions or files are seeded — official curriculum content must be entered and
> verified by an administrator.

## 3. Authentication

**Authentication → Providers**

- **Anonymous sign-ins: ON** (used by "كمل بدون حساب" so students can read published content without Google).
- **Email: ON** (only used by administrators to log in to the dashboard; disable "Confirm email" or confirm
  admin users manually).
- **Google: ON** — see §4.

**Authentication → URL Configuration → Redirect URLs**: add `com.enjaz.student://login-callback`
and the URL where you host the admin dashboard.

## 4. Google sign-in (Google Cloud, free)

1. <https://console.cloud.google.com> → create a project → **APIs & Services → OAuth consent screen**
   (External, app name «إنجاز», support email, scopes: `email`, `profile`, `openid`).
2. **Credentials → Create credentials → OAuth client ID → Web application**.
   - Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`
3. Copy **Client ID** and **Client secret** into Supabase → Authentication → Providers → Google. Save.

The app uses Supabase's browser-based Google flow, so no Android SHA-1 or `google-services.json` is needed
for sign-in. The app never sees or stores the Google password.

## 5. Push notifications (Firebase Cloud Messaging, free)

1. <https://console.firebase.google.com> → **Add project** (Analytics optional).
2. **Project settings → General → Your apps → Add app → Android**, package name `com.enjaz.student`.
   From the generated config copy: **API key**, **App ID** (`1:…:android:…`), **Sender ID** (project number),
   **Project ID**. These are public client options.
3. **Project settings → Service accounts → Generate new private key** → a JSON file.
   This is a **server secret**: put its whole content in Supabase → Edge Functions → **Secrets** as
   `FCM_SERVICE_ACCOUNT`. Never commit it or put it in the app/dashboard.
4. Also add a secret `CRON_SECRET` (any long random string).
5. Schedule automatic sending of scheduled campaigns (SQL Editor, replace the placeholders):

```sql
select vault.create_secret('<CRON_SECRET value>', 'enjaz_cron_secret');
select cron.schedule('enjaz-send-notifications', '* * * * *', $$
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/send-notifications',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'enjaz_cron_secret')),
    body := '{}'::jsonb)
$$);
```

Without `FCM_SERVICE_ACCOUNT` the function marks campaigns **failed: fcm_not_configured** — it never
pretends a notification was sent.

## 6. Create the first administrator (no public registration exists)

1. **Authentication → Users → Add user** → email + strong password, "Auto confirm".
2. SQL Editor:

```sql
insert into public.admin_roles (user_id, role)
select id, 'super_admin' from auth.users where email = 'you@example.com';
```

3. Log in to the dashboard with that email/password. Further admins can be added from **المشرفون**
   (they must have signed in once). Roles: `super_admin` (everything + admins), `admin` (+ students, versions,
   settings), `editor` (content only). Enforcement is in RLS, not in the UI.

## 7. Connect the apps

GitHub → repository **Settings → Secrets and variables → Actions → Variables** (these are public values):

| Variable | Value |
|---|---|
| `ENJAZ_SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `ENJAZ_SUPABASE_ANON_KEY` | anon / publishable key |
| `ENJAZ_FIREBASE_API_KEY`, `ENJAZ_FIREBASE_APP_ID`, `ENJAZ_FIREBASE_SENDER_ID`, `ENJAZ_FIREBASE_PROJECT_ID` | from §5.2 |

Re-run **ENJAZ — Student app (APK)** and **ENJAZ — Admin dashboard**. The build summary shows
`Backend configured: true`.

## Free-tier limits to know

| Service | Free limits (check current pricing pages) | Effect |
|---|---|---|
| Supabase Free | 500 MB database, 1 GB file storage, 5 GB egress/month, 50k monthly active users; project **pauses after 1 week of inactivity** (restore from dashboard) | Large PDF libraries need the paid plan or external hosting |
| Firebase Spark | FCM is free | — |
| Google OAuth | Free; unverified apps show a warning screen until verified | Submit for verification before wide release |
| GitHub Actions | Free minutes on public repos; limited monthly minutes on private repos | APK build ≈ 8 min |
