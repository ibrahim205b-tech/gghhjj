# Deployment & releases

## Student app (APK)

- Built by **.github/workflows/enjaz-student.yml** on every change under `apps/student/`.
- Download: GitHub → **Actions → "ENJAZ — Student app (APK)"** → latest green run → **Artifacts → ENJAZ-apk**
  (zip containing `ENJAZ.apk` + SHA-256).
- Install: open `ENJAZ.apk` on the phone → allow "install unknown apps" for the browser/file manager → Install.

### Release signing (do this before giving the app to students)

Without signing secrets the APK is signed with the CI runner's debug key, which can change between runs;
Android refuses to update an app signed with a different key. Create **one** key and keep it forever:

```bash
keytool -genkey -v -keystore enjaz-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias enjaz
base64 -w0 enjaz-release.jks > enjaz-release.b64
```

Add repository **secrets** `ENJAZ_KEYSTORE_BASE64`, `ENJAZ_KEYSTORE_PASSWORD`, `ENJAZ_KEY_ALIAS`,
`ENJAZ_KEY_PASSWORD`. The workflow writes `key.properties` temporarily and deletes it after the build.
Back up the `.jks` and passwords offline — losing them means students must uninstall to update.

### Publishing an update

1. Bump `version:` in `apps/student/pubspec.yaml` (e.g. `1.1.0+2` — the number after `+` is the build number).
2. Push → CI builds the new `ENJAZ.apk` (same package id `com.enjaz.student`, same signing key).
3. Upload the APK where students download it (Telegram channel, your website) — or Google Play.
4. Admin dashboard → **تحديثات التطبيق** → add version `1.1.0`, build `2`, links, description, image,
   optional/mandatory, minimum supported build → publish.
   Students then see «أكو تحديث جديد…» with **حدّث التطبيق / افتح قناة التليجرام / لاحقاً**.
   The app never installs silently and never deletes local data; installing over the old version keeps all data.

## Admin dashboard (static website)

- Built by **.github/workflows/enjaz-admin.yml** → **Artifacts → ENJAZ-admin-dashboard** (`dist/`).
- It is a static single-page app (hash routing) that talks only to Supabase, so it can be hosted on any
  static host. Free options without a card: **Cloudflare Pages** (drag & drop the `dist` folder),
  **Netlify** (drag & drop), or **GitHub Pages** (public repositories).
- Local run: `cd apps/admin && cp .env.example .env` (fill the two public values) → `npm ci && npm run dev`.
- The page sends `noindex`. Security does not depend on hiding the URL: every action is checked by RLS.

## Backend

See [BACKEND_SETUP.md](BACKEND_SETUP.md). Database changes = new files in `supabase/migrations/`
(never edit an applied migration) → `supabase db push`.
