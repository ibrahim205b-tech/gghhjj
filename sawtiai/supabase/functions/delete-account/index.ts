// ENJAZ — permanent account deletion requested by the student from the app.
// Deleting the auth user cascades to every personal row (FK ON DELETE CASCADE).
// Administrators cannot delete themselves through this endpoint.

import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  })
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  const { data: u } = await admin.auth.getUser(jwt)
  if (!u?.user) return json({ error: 'unauthorized' }, 401)
  const uid = u.user.id

  const { data: isAdmin } = await admin.from('admin_roles').select('user_id').eq('user_id', uid).maybeSingle()
  if (isAdmin) return json({ error: 'admins_must_be_removed_by_a_super_admin_first' }, 409)

  const { data: profile } = await admin.from('profiles').select('status').eq('id', uid).maybeSingle()
  if (profile?.status !== 'deletion_requested') return json({ error: 'call request_account_deletion first' }, 409)

  // Remove the student's avatar files, then the account itself.
  const { data: files } = await admin.storage.from('avatars').list(uid)
  if (files?.length) await admin.storage.from('avatars').remove(files.map((f) => `${uid}/${f.name}`))
  const { error } = await admin.auth.admin.deleteUser(uid)
  if (error) return json({ error: error.message }, 500)
  return json({ deleted: true })
})
