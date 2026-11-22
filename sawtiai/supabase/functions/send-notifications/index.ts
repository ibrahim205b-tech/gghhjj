// ENJAZ — push notification dispatcher (Supabase Edge Function, Deno).
//
// Called by:
//   * the admin dashboard (Authorization: Bearer <admin user JWT>, body {campaign_id})
//   * the scheduler every minute (header x-cron-secret: CRON_SECRET) to send due campaigns
// Secrets (Supabase -> Edge Functions -> Secrets, never in git or the apps):
//   FCM_SERVICE_ACCOUNT  JSON of a Firebase service account (Cloud Messaging)
//   CRON_SECRET          random string shared with the pg_cron job
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

interface ServiceAccount { client_email: string; private_key: string; project_id: string }

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data)
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** OAuth2 access token for FCM HTTP v1 from a service account (RS256 JWT). */
async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = b64url(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  }))
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`))
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${claims}.${b64url(sig)}` }),
  })
  if (!res.ok) throw new Error(`oauth ${res.status}: ${await res.text()}`)
  return (await res.json()).access_token
}

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>

async function recipients(admin: SupabaseClient, c: Row): Promise<{ user_id: string; token_id: string; token: string }[]> {
  let users: string[] | null = null
  if (c.audience === 'user') {
    users = [c.target_user_id]
  } else if (c.audience !== 'all') {
    let q = admin.from('student_academic_profiles').select('user_id')
    if (c.audience === 'stage') q = q.in('stage_id', c.target_stage_ids)
    if (c.audience === 'grade') q = q.in('grade_id', c.target_grade_ids)
    if (c.audience === 'branch') q = q.in('branch_id', c.target_branch_ids)
    const { data, error } = await q
    if (error) throw error
    users = (data ?? []).map((r) => r.user_id)
  }
  let tq = admin.from('device_tokens').select('id, user_id, token')
  if (users) {
    if (!users.length) return []
    tq = tq.in('user_id', users)
  }
  const { data: tokens, error } = await tq.limit(50000)
  if (error) throw error
  // Respect the student's notification preferences for this category.
  const prefKey = `notify_${c.category ?? 'announcements'}`
  const uids = [...new Set((tokens ?? []).map((t) => t.user_id))]
  const optedOut = new Set<string>()
  for (let i = 0; i < uids.length; i += 500) {
    const { data: prefs } = await admin.from('user_preferences').select(`user_id, ${prefKey}`).in('user_id', uids.slice(i, i + 500))
    for (const p of prefs ?? []) if ((p as Row)[prefKey] === false) optedOut.add((p as Row).user_id)
  }
  const { data: suspended } = await admin.from('profiles').select('id').eq('status', 'suspended').in('id', uids.slice(0, 1000))
  for (const s of suspended ?? []) optedOut.add(s.id)
  return (tokens ?? []).filter((t) => !optedOut.has(t.user_id)).map((t) => ({ user_id: t.user_id, token_id: t.id, token: t.token }))
}

async function sendCampaign(admin: SupabaseClient, c: Row, sa: ServiceAccount | null): Promise<Row> {
  // Claim the campaign atomically so two runs never send it twice.
  const { data: claimed } = await admin.from('notification_campaigns').update({ status: 'sending' })
    .eq('id', c.id).in('status', ['scheduled', 'failed']).select('id')
  if (!claimed?.length) return { id: c.id, skipped: true }
  if (!sa) {
    await admin.from('notification_campaigns').update({ status: 'failed', last_error: 'fcm_not_configured: set the FCM_SERVICE_ACCOUNT secret' }).eq('id', c.id)
    return { id: c.id, error: 'fcm_not_configured' }
  }
  try {
    const list = await recipients(admin, c)
    const token = await fcmAccessToken(sa)
    let ok = 0, fail = 0
    const rows: Row[] = []
    const stale: string[] = []
    for (let i = 0; i < list.length; i += 50) {
      const batch = list.slice(i, i + 50)
      await Promise.all(batch.map(async (r) => {
        const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: {
            token: r.token,
            notification: { title: c.title, body: c.body, ...(c.image_url ? { image: c.image_url } : {}) },
            data: { deep_link: c.deep_link ?? '', campaign_id: c.id },
            android: { priority: 'high', notification: { channel_id: 'general' } },
          } }),
        })
        const delivered = res.ok
        let error: string | null = null
        if (!delivered) {
          error = `${res.status}`
          const text = await res.text()
          if (res.status === 404 || text.includes('UNREGISTERED')) stale.push(r.token_id)
        }
        delivered ? ok++ : fail++
        rows.push({ campaign_id: c.id, user_id: r.user_id, token_id: r.token_id, delivered, error })
      }))
    }
    for (let i = 0; i < rows.length; i += 500) await admin.from('notification_recipients').insert(rows.slice(i, i + 500))
    if (stale.length) await admin.from('device_tokens').delete().in('id', stale)
    const status = list.length === 0 || ok > 0 ? 'sent' : 'failed'
    await admin.from('notification_campaigns').update({
      status, sent_at: new Date().toISOString(), total_recipients: list.length, success_count: ok, failure_count: fail,
      last_error: list.length === 0 ? 'no_recipients' : fail && !ok ? 'all_failed' : null,
    }).eq('id', c.id)
    return { id: c.id, recipients: list.length, ok, fail }
  } catch (e) {
    await admin.from('notification_campaigns').update({ status: 'failed', last_error: String(e).slice(0, 500) }).eq('id', c.id)
    return { id: c.id, error: String(e) }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const url = Deno.env.get('SUPABASE_URL')!
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(url, service, { auth: { persistSession: false } })

  const cronSecret = Deno.env.get('CRON_SECRET')
  const isCron = !!cronSecret && req.headers.get('x-cron-secret') === cronSecret
  if (!isCron) {
    // Only authenticated administrators may trigger sending.
    const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
    const { data: u } = await admin.auth.getUser(jwt)
    if (!u?.user) return json({ error: 'unauthorized' }, 401)
    const { data: role } = await admin.from('admin_roles').select('role').eq('user_id', u.user.id).maybeSingle()
    if (!role) return json({ error: 'forbidden' }, 403)
  }

  let sa: ServiceAccount | null = null
  try {
    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    sa = raw ? JSON.parse(raw) : null
  } catch {
    sa = null
  }

  const body = await req.json().catch(() => ({}))
  let q = admin.from('notification_campaigns').select('*')
  if (body.campaign_id) q = q.eq('id', body.campaign_id).in('status', ['scheduled', 'failed'])
  else q = q.eq('status', 'scheduled').lte('scheduled_at', new Date().toISOString()).limit(20)
  const { data: due, error } = await q
  if (error) return json({ error: error.message }, 500)
  const results = []
  for (const c of due ?? []) results.push(await sendCampaign(admin, c, sa))
  return json({ processed: results.length, results })
})
