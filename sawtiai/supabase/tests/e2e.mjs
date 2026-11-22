// End-to-end test against a REAL local Supabase stack (supabase start):
// PostgREST + GoTrue + Storage + Edge Functions + Postgres with our migrations.
// Run: SUPABASE_URL=... ANON_KEY=... SERVICE_KEY=... node supabase/tests/e2e.mjs
import { createClient } from '@supabase/supabase-js'
import assert from 'node:assert/strict'

const url = process.env.SUPABASE_URL
const anonKey = process.env.ANON_KEY
const serviceKey = process.env.SERVICE_KEY
const service = createClient(url, serviceKey, { auth: { persistSession: false } })
const fresh = () => createClient(url, anonKey, { auth: { persistSession: false } })
let passed = 0
const ok = (msg) => { passed++; console.log(`  ✔ ${msg}`) }

// --- provision an administrator the documented way (service role, never the UI) ---
const adminEmail = `admin-${Date.now()}@enjaz.test`
const adminPassword = crypto.randomUUID()
const { data: au, error: aue } = await service.auth.admin.createUser({ email: adminEmail, password: adminPassword, email_confirm: true })
assert.ifError(aue)
assert.ifError((await service.from('admin_roles').insert({ user_id: au.user.id, role: 'super_admin' })).error)
ok('admin provisioned with service role')

const admin = fresh()
assert.ifError((await admin.auth.signInWithPassword({ email: adminEmail, password: adminPassword })).error)
const role = await admin.from('admin_roles').select('role').eq('user_id', au.user.id).single()
assert.equal(role.data.role, 'super_admin')
ok('admin signs in; role visible to self')

// --- admin builds content ---
const g12 = (await admin.from('grades').select('*').eq('code', 'grade_12').single()).data
const applied = (await admin.from('academic_branches').select('*').eq('grade_id', g12.id).eq('code', 'applied').single()).data
const subj = (await admin.from('subjects').insert({ grade_id: g12.id, name_ar: 'الرياضيات', is_verified: false }).select().single())
assert.ifError(subj.error)
const ch = (await admin.from('chapters').insert({ subject_id: subj.data.id, title: 'الأعداد المركبة' }).select().single()).data
const q = await admin.from('questions').insert({
  grade_id: g12.id, subject_id: subj.data.id, chapter_id: ch.id, question_type: 'true_false',
  question_text: 'i² = -1', status: 'published',
}).select().single()
assert.ifError(q.error)
assert.ifError((await admin.from('question_options').insert([
  { question_id: q.data.id, option_text: 'صح', is_correct: true, sort_order: 1 },
  { question_id: q.data.id, option_text: 'خطأ', is_correct: false, sort_order: 2 },
])).error)
const draft = await admin.from('questions').insert({ grade_id: g12.id, subject_id: subj.data.id, question_type: 'short_answer',
  question_text: 'draft', answer_text: 'x', status: 'draft' }).select().single()
assert.ifError(draft.error)
const ann = await admin.from('announcements').insert({ title: 'هلا بيك بإنجاز', status: 'published', target_all: true }).select().single()
assert.ifError(ann.error)
const ver = await admin.from('app_versions').insert({ version_name: '1.1.0', build_number: 2, download_url: 'https://example.org/ENJAZ.apk',
  telegram_url: 'https://t.me/enjaz', status: 'published' }).select().single()
assert.ifError(ver.error)
ok('admin creates subject, chapter, questions, announcement, app version')

// storage: admin uploads a PDF to the private library bucket
const pdf = new Blob(['%PDF-1.4\n%enjaz test\n'], { type: 'application/pdf' })
const up = await admin.storage.from('library').upload(`files/${crypto.randomUUID()}.pdf`, pdf, { contentType: 'application/pdf' })
assert.ifError(up.error)
const lf = await admin.from('library_files').insert({ grade_id: g12.id, subject_id: subj.data.id, title: 'ملزمة',
  storage_path: up.data.path, mime_type: 'application/pdf', size_bytes: 22, status: 'published' }).select().single()
assert.ifError(lf.error)
ok('admin uploads a library PDF')

const logs = await admin.from('admin_activity_logs').select('*').eq('admin_id', au.user.id)
assert.ok(logs.data.length >= 6, 'activity logged')
ok(`activity log recorded ${logs.data.length} admin actions`)

// --- student (anonymous session = "continue without account") ---
const student = fresh()
const anon = await student.auth.signInAnonymously()
assert.ifError(anon.error)
const sid = anon.data.user.id
assert.ifError((await student.from('student_academic_profiles').insert({
  user_id: sid, stage_id: g12.stage_id, grade_id: g12.id, branch_id: applied.id })).error)
ok('student signs in anonymously and sets grade 12 / applied')

const sq = await student.from('questions').select('question_text')
assert.deepEqual(sq.data.map((x) => x.question_text), ['i² = -1'])
ok('student sees only published questions (draft hidden)')
assert.equal((await student.from('question_options').select('*')).data.length, 2)
assert.equal((await student.from('announcements').select('*')).data.length, 1)
assert.equal((await student.from('app_versions').select('*')).data[0].build_number, 2)
ok('student reads options, announcement and update info')

const signed = await student.storage.from('library').createSignedUrl(up.data.path, 60)
assert.ifError(signed.error)
const dl = await fetch(signed.data.signedUrl)
assert.equal(dl.status, 200)
assert.ok((await dl.text()).startsWith('%PDF'))
ok('student downloads the published PDF through a signed URL')

// student writes are rejected on admin tables
const hack = await student.from('questions').insert({ grade_id: g12.id, subject_id: subj.data.id, question_type: 'true_false', question_text: 'x' })
assert.ok(hack.error, 'student insert into questions must fail')
const esc = await student.from('admin_roles').insert({ user_id: sid, role: 'super_admin' })
assert.ok(esc.error, 'privilege escalation must fail')
const ov = await student.rpc('admin_overview')
assert.ok(ov.error, 'admin rpc must fail for students')
ok('student cannot write content, escalate privileges or call admin RPCs')

// offline-sync style upsert with client ids and last-write-wins
const taskId = crypto.randomUUID()
assert.ifError((await student.from('study_tasks').upsert({ id: taskId, user_id: sid, title: 'جديد', client_modified_at: '2026-11-22T10:00:00Z' })).error)
assert.ifError((await student.from('study_tasks').upsert({ id: taskId, user_id: sid, title: 'قديم', client_modified_at: '2026-11-22T09:00:00Z' })).error)
assert.equal((await student.from('study_tasks').select('title').eq('id', taskId).single()).data.title, 'جديد')
ok('sync upserts work and an older write never overwrites a newer one')

assert.ifError((await student.from('device_tokens').insert({ user_id: sid, token: `test-token-${Date.now()}` })).error)
assert.ifError((await student.rpc('mark_announcement_seen', { p_id: ann.data.id, p_ack: true })).error)
const exp = await student.rpc('export_my_data')
assert.equal(exp.data.tasks.length, 1)
ok('device token registered, acknowledgment recorded, data export works')

// another student cannot see the first one's data
const other = fresh()
await other.auth.signInAnonymously()
assert.equal((await other.from('study_tasks').select('*')).data.length, 0)
ok('students are isolated from each other')

// --- admin views the student, suspends and restores ---
const list = await admin.rpc('admin_list_students', { p_grade: g12.id })
assert.ok(list.data.some((s) => s.id === sid))
assert.ifError((await admin.rpc('admin_set_student_status', { p_user: sid, p_status: 'suspended', p_reason: 'test' })).error)
const blocked = await student.from('study_tasks').insert({ id: crypto.randomUUID(), user_id: sid, title: 'blocked' })
assert.ok(blocked.error, 'suspended student cannot write')
assert.ifError((await admin.rpc('admin_set_student_status', { p_user: sid, p_status: 'active' })).error)
ok('admin lists, suspends (writes blocked) and restores the student')

// --- push notifications through the real Edge Function ---
const camp = await admin.from('notification_campaigns').insert({ title: 'هلا بيك!', body: 'نزلنا إلك أسئلة جديدة', audience: 'grade',
  target_grade_ids: [g12.id], status: 'scheduled', scheduled_at: new Date().toISOString() }).select().single()
assert.ifError(camp.error)
const denied = await student.functions.invoke('send-notifications', { body: { campaign_id: camp.data.id } })
assert.ok(denied.error, 'students cannot trigger sending')
const send = await admin.functions.invoke('send-notifications', { body: { campaign_id: camp.data.id } })
assert.ifError(send.error)
const after = (await admin.from('notification_campaigns').select('*').eq('id', camp.data.id).single()).data
if (process.env.EXPECT_FCM === '1') {
  assert.equal(after.status, 'sent')
} else {
  // Without Firebase credentials the function must report it, never pretend.
  assert.equal(after.status, 'failed')
  assert.match(after.last_error, /fcm_not_configured/)
}
ok(`edge function send-notifications ran: status=${after.status}${after.last_error ? ` (${after.last_error})` : ''}`)

// --- account deletion ---
assert.ifError((await student.rpc('request_account_deletion')).error)
const del = await student.functions.invoke('delete-account', { method: 'POST' })
assert.ifError(del.error)
const gone = await service.from('study_tasks').select('*').eq('user_id', sid)
assert.equal(gone.data.length, 0)
const goneUser = await service.auth.admin.getUserById(sid)
assert.ok(goneUser.error || !goneUser.data.user)
ok('account deletion removes the user and all personal data')

console.log(`\nALL ${passed} E2E CHECKS PASSED`)
