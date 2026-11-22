import { useCallback, useEffect, useState } from 'react'
import { db, publicUrl, uploadFile, type Row } from '../lib/supabase'
import { t } from '../lib/strings'
import { Badge, Button, Card, Field, Modal, PageHeader, StatusBadge, fmtDate, toast } from '../components/ui'
import { CrudPage, FieldInput, useRefs, type FieldDef } from '../components/CrudPage'

const MAX_LIBRARY_BYTES = 100 * 1024 * 1024
const LIBRARY_TYPES = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp']

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------
const LFIELDS: FieldDef[] = [
  { key: 'category_id', label: t.category, type: 'ref', ref: { table: 'library_categories', label: 'name_ar' } },
  { key: 'grade_id', label: t.grade, type: 'ref', ref: { table: 'grades', label: 'name_ar' } },
  { key: 'branch_id', label: t.branch, type: 'ref', ref: { table: 'academic_branches', label: 'name_ar', filter: { grade_id: '$grade_id' } } },
  { key: 'subject_id', label: t.subject, type: 'ref', ref: { table: 'subjects', label: 'name_ar', filter: { grade_id: '$grade_id' } } },
  { key: 'chapter_id', label: t.chapter, type: 'ref', ref: { table: 'chapters', label: 'title', filter: { subject_id: '$subject_id' } } },
  { key: 'cover_path', label: t.cover, type: 'image' },
  { key: 'source', label: t.source, type: 'text' },
  { key: 'status', label: t.status, type: 'select', required: true, options: ['draft', 'scheduled', 'published', 'archived'].map((v) => ({ value: v, label: t[v as 'draft'] })) },
  { key: 'publish_at', label: t.publishAt, type: 'datetime' },
  { key: 'expires_at', label: t.expiresAt, type: 'datetime' },
]

export function LibraryPage() {
  const refs = useRefs(LFIELDS)
  const [rows, setRows] = useState<Row[]>([])
  const [editing, setEditing] = useState<Row | null>(null)
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const load = useCallback(async () => {
    const { data, error } = await db().from('library_files').select('*').is('deleted_at', null).order('created_at', { ascending: false }).limit(500)
    if (error) toast(error.message, true)
    setRows(data ?? [])
  }, [])
  useEffect(() => { void load() }, [load])

  const save = async () => {
    if (!editing) return
    if (!String(editing.title ?? '').trim()) return toast(`${t.title}: ${t.required}`, true)
    if (!editing.id && !file) return toast(`${t.file}: ${t.required}`, true)
    if (editing.status === 'scheduled' && !editing.publish_at) return toast(`${t.publishAt}: ${t.required}`, true)
    if (file) {
      if (!LIBRARY_TYPES.includes(file.type)) return toast(t.fileTypeInvalid, true)
      if (file.size > MAX_LIBRARY_BYTES) return toast(t.fileTooLarge, true)
    }
    setBusy(true)
    try {
      const payload: Row = { ...editing }
      if (file) {
        const oldPath = editing.storage_path
        payload.storage_path = await uploadFile('library', file, 'files')
        payload.mime_type = file.type
        payload.size_bytes = file.size
        if (oldPath) await db().storage.from('library').remove([oldPath])
      }
      for (const k of Object.keys(payload)) if (payload[k] === '') payload[k] = null
      const { error } = await db().from('library_files').upsert(payload)
      if (error) throw error
      toast(t.saved)
      setEditing(null)
      setFile(null)
      void load()
    } catch (e) {
      toast((e as Error).message, true)
    } finally {
      setBusy(false)
    }
  }

  const remove = async (r: Row) => {
    if (!confirm(t.confirmDelete)) return
    await db().storage.from('library').remove([r.storage_path])
    const { error } = await db().from('library_files').update({ deleted_at: new Date().toISOString(), status: 'archived' }).eq('id', r.id)
    if (error) return toast(error.message, true)
    void load()
  }

  const quick = async (r: Row, status: string) => {
    await db().from('library_files').update({ status, publish_at: status === 'published' ? new Date().toISOString() : r.publish_at }).eq('id', r.id)
    void load()
  }

  return (
    <div>
      <PageHeader title={t.library} actions={<Button onClick={() => { setFile(null); setEditing({ status: 'draft' }) }}>+ {t.upload}</Button>} />
      <Card>
        <div className="overflow-x-auto">
          <table>
            <thead><tr><th /><th>{t.title}</th><th>{t.grade}</th><th>{t.subject}</th><th>الحجم</th><th>{t.downloads}</th><th>{t.status}</th><th>{t.actions}</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>{publicUrl(r.cover_path) ? <img src={publicUrl(r.cover_path)!} alt="" className="h-12 w-9 rounded object-cover" /> : '📄'}</td>
                  <td>{r.title}</td>
                  <td>{refs.grades?.find((g) => g.id === r.grade_id)?.name_ar ?? t.all}</td>
                  <td>{refs.subjects?.find((s) => s.id === r.subject_id)?.name_ar ?? '—'}</td>
                  <td dir="ltr">{(r.size_bytes / 1048576).toFixed(1)} MB</td>
                  <td>{r.download_count}</td>
                  <td><StatusBadge status={r.status} /> {r.status === 'scheduled' && <span className="text-xs text-muted">{fmtDate(r.publish_at)}</span>}</td>
                  <td className="whitespace-nowrap">
                    <div className="flex flex-wrap gap-1">
                      <Button variant="ghost" onClick={() => { setFile(null); setEditing({ ...r }) }}>{t.edit}</Button>
                      {r.status !== 'published' ? <Button variant="ghost" onClick={() => quick(r, 'published')}>{t.publishNow}</Button>
                        : <Button variant="ghost" onClick={() => quick(r, 'draft')}>{t.unpublish}</Button>}
                      <Button variant="danger" onClick={() => remove(r)}>{t.delete}</Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
      <Modal open={!!editing} title={editing?.id ? t.edit : t.upload} onClose={() => setEditing(null)} wide>
        {editing && (
          <div className="grid gap-4 md:grid-cols-2">
            <Field label={`${t.title} *`}><input value={editing.title ?? ''} onChange={(e) => setEditing({ ...editing, title: e.target.value })} /></Field>
            <Field label={editing.id ? t.replaceFile : `${t.file} *`} hint="PDF أو صورة — حتى 100 ميغابايت">
              <input type="file" accept=".pdf,image/jpeg,image/png,image/webp" className="!w-auto" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            </Field>
            <div className="md:col-span-2"><Field label={t.description}><textarea rows={3} value={editing.description ?? ''} onChange={(e) => setEditing({ ...editing, description: e.target.value })} /></Field></div>
            {LFIELDS.map((f) => (
              <Field key={f.key} label={f.label}>
                <FieldInput f={f} value={editing[f.key]} values={editing} refs={refs} onChange={(v) => setEditing({ ...editing, [f.key]: v })} />
              </Field>
            ))}
            <div className="flex gap-2 md:col-span-2">
              <Button onClick={save} busy={busy}>{t.save}</Button>
              <Button variant="ghost" onClick={() => setEditing(null)}>{t.cancel}</Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Announcements (with targeting rows in announcement_targets)
// ---------------------------------------------------------------------------
const AFIELDS: FieldDef[] = [
  { key: 'kind', label: t.kind, type: 'select', required: true, options: [
    { value: 'general', label: 'عام' }, { value: 'content', label: 'محتوى جديد' }, { value: 'exam_schedule', label: 'جدول امتحانات' },
    { value: 'notice', label: 'تنبيه مهم' }, { value: 'telegram', label: 'قناة تليجرام' }, { value: 'app_update', label: 'تحديث التطبيق' }] },
  { key: 'title', label: t.title, type: 'text', required: true },
  { key: 'description', label: t.description, type: 'textarea' },
  { key: 'image_path', label: t.image, type: 'image' },
  { key: 'action_label', label: t.actionLabel, type: 'text' },
  { key: 'action_url', label: t.actionUrl, type: 'url' },
  { key: 'telegram_url', label: t.telegramUrl, type: 'url' },
  { key: 'priority', label: t.priority, type: 'number' },
  { key: 'display_frequency', label: t.frequency, type: 'select', required: true, options: [
    { value: 'once', label: t.once }, { value: 'until_acknowledged', label: t.untilAck }, { value: 'every_launch', label: t.everyLaunch }] },
  { key: 'requires_acknowledgment', label: t.requiresAck, type: 'bool' },
  { key: 'target_all', label: t.targetAll, type: 'bool' },
  { key: '_stages', label: t.targetStages, type: 'refMulti', ref: { table: 'academic_stages', label: 'name_ar' }, showIf: (v) => !v.target_all },
  { key: '_grades', label: t.targetGrades, type: 'refMulti', ref: { table: 'grades', label: 'name_ar' }, showIf: (v) => !v.target_all },
  { key: '_branches', label: t.targetBranches, type: 'refMulti', ref: { table: 'academic_branches', label: 'name_ar' }, showIf: (v) => !v.target_all },
  { key: 'status', label: t.status, type: 'select', required: true, options: ['draft', 'scheduled', 'published', 'archived'].map((v) => ({ value: v, label: t[v as 'draft'] })) },
  { key: 'publish_at', label: t.publishAt, type: 'datetime' },
  { key: 'expires_at', label: t.expiresAt, type: 'datetime' },
]

export function validateAnnouncement(v: Row): string | null {
  if (!String(v.title ?? '').trim()) return `${t.title}: ${t.required}`
  if (v.action_url && !/^(https:\/\/|enjaz:\/\/)/.test(v.action_url)) return 'رابط الزر يجب أن يبدأ بـ https:// أو enjaz://'
  if (v.telegram_url && !/^https:\/\/(t\.me|telegram\.me)\//.test(v.telegram_url)) return 'رابط التليجرام يجب أن يبدأ بـ https://t.me/'
  if (!v.target_all && !(v._stages?.length || v._grades?.length || v._branches?.length)) return 'اختر جمهوراً أو فعّل «لكل الطلاب»'
  if (v.status === 'scheduled' && !v.publish_at) return `${t.publishAt}: ${t.required}`
  if (v.publish_at && v.expires_at && new Date(v.expires_at) <= new Date(v.publish_at)) return 'تاريخ الانتهاء يجب أن يكون بعد النشر'
  return null
}

export function AnnouncementsPage() {
  const refs = useRefs(AFIELDS)
  const [rows, setRows] = useState<Row[]>([])
  const [editing, setEditing] = useState<Row | null>(null)
  const [busy, setBusy] = useState(false)
  const load = useCallback(async () => {
    const { data, error } = await db().from('announcements').select('*, announcement_targets(*), announcement_acknowledgments(count)')
      .is('deleted_at', null).order('created_at', { ascending: false }).limit(300)
    if (error) toast(error.message, true)
    setRows(data ?? [])
  }, [])
  useEffect(() => { void load() }, [load])

  const open = (r?: Row) => {
    if (!r) return setEditing({ kind: 'general', display_frequency: 'once', status: 'draft', target_all: true, priority: 0, requires_acknowledgment: false })
    const tg = (r.announcement_targets as Row[]) ?? []
    setEditing({ ...r, _stages: tg.filter((x) => x.stage_id).map((x) => x.stage_id), _grades: tg.filter((x) => x.grade_id).map((x) => x.grade_id),
      _branches: tg.filter((x) => x.branch_id).map((x) => x.branch_id) })
  }

  const save = async () => {
    if (!editing) return
    const err = validateAnnouncement(editing)
    if (err) return toast(err, true)
    setBusy(true)
    const payload: Row = {}
    for (const f of AFIELDS) if (!f.key.startsWith('_') && f.key in editing) payload[f.key] = editing[f.key] === '' ? null : editing[f.key]
    if (editing.id) payload.id = editing.id
    const { data, error } = await db().from('announcements').upsert(payload).select('id').single()
    if (error) {
      setBusy(false)
      return toast(error.message, true)
    }
    await db().from('announcement_targets').delete().eq('announcement_id', data.id)
    if (!editing.target_all) {
      const targets = [
        ...((editing._stages as string[]) ?? []).map((id) => ({ announcement_id: data.id, stage_id: id })),
        ...((editing._grades as string[]) ?? []).map((id) => ({ announcement_id: data.id, grade_id: id })),
        ...((editing._branches as string[]) ?? []).map((id) => ({ announcement_id: data.id, branch_id: id })),
      ]
      if (targets.length) await db().from('announcement_targets').insert(targets)
    }
    setBusy(false)
    toast(t.saved)
    setEditing(null)
    void load()
  }

  const quick = async (r: Row, patch: Row) => {
    await db().from('announcements').update(patch).eq('id', r.id)
    void load()
  }

  return (
    <div>
      <PageHeader title={t.announcements} actions={<Button onClick={() => open()}>+ {t.add}</Button>} />
      <Card>
        <div className="overflow-x-auto">
          <table>
            <thead><tr><th /><th>{t.title}</th><th>{t.kind}</th><th>{t.frequency}</th><th>الجمهور</th><th>تأكيدات</th><th>{t.status}</th><th>{t.actions}</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>{publicUrl(r.image_path) ? <img src={publicUrl(r.image_path)!} alt="" className="h-10 w-16 rounded object-cover" /> : '📢'}</td>
                  <td>{r.title}</td>
                  <td>{r.kind}</td>
                  <td>{{ once: t.once, until_acknowledged: t.untilAck, every_launch: t.everyLaunch }[r.display_frequency as string]}</td>
                  <td>{r.target_all ? <Badge color="success">{t.all}</Badge> : <Badge color="warning">{(r.announcement_targets as Row[])?.length ?? 0} استهداف</Badge>}</td>
                  <td>{(r.announcement_acknowledgments as Row[])?.[0]?.count ?? 0}</td>
                  <td><StatusBadge status={r.status} /></td>
                  <td className="whitespace-nowrap">
                    <div className="flex flex-wrap gap-1">
                      <Button variant="ghost" onClick={() => open(r)}>{t.edit}</Button>
                      {r.status !== 'published' ? <Button variant="ghost" onClick={() => quick(r, { status: 'published', publish_at: new Date().toISOString() })}>{t.publishNow}</Button>
                        : <Button variant="ghost" onClick={() => quick(r, { status: 'draft' })}>{t.unpublish}</Button>}
                      <Button variant="danger" onClick={() => confirm(t.confirmDelete) && quick(r, { deleted_at: new Date().toISOString() })}>{t.delete}</Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
      <Modal open={!!editing} title={editing?.id ? t.edit : t.add} onClose={() => setEditing(null)} wide>
        {editing && (
          <div className="grid gap-4 md:grid-cols-2">
            {AFIELDS.filter((f) => f.showIf?.(editing) ?? true).map((f) => (
              <div key={f.key} className={f.type === 'textarea' || f.type === 'refMulti' ? 'md:col-span-2' : ''}>
                <Field label={f.label + (f.required ? ' *' : '')}>
                  <FieldInput f={f} value={editing[f.key]} values={editing} refs={refs} onChange={(v) => setEditing({ ...editing, [f.key]: v })} />
                </Field>
              </div>
            ))}
            <div className="md:col-span-2">
              <p className="mb-2 text-sm text-muted">{t.preview}</p>
              <div className="max-w-sm overflow-hidden rounded-3xl border border-white/10 bg-navy-surface">
                {publicUrl(editing.image_path) && <img src={publicUrl(editing.image_path)!} alt="" className="w-full" />}
                <div className="p-4">
                  <Badge color="cyan">إعلان</Badge>
                  <p className="mt-2 text-lg font-bold">{editing.title || '…'}</p>
                  <p className="text-sm text-muted">{editing.description}</p>
                  {editing.action_url && <div className="btn-brand mt-3 rounded-full py-2 text-center text-white">{editing.action_label || 'افتح'}</div>}
                  {editing.telegram_url && <div className="mt-2 rounded-full border border-white/20 py-2 text-center">افتح قناة التليجرام</div>}
                </div>
              </div>
            </div>
            <div className="flex gap-2 md:col-span-2">
              <Button onClick={save} busy={busy}>{t.save}</Button>
              <Button variant="ghost" onClick={() => setEditing(null)}>{t.cancel}</Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Push notification campaigns (delivered by the send-notifications Edge Function)
// ---------------------------------------------------------------------------
export function validateCampaign(v: Row): string | null {
  if (!String(v.title ?? '').trim() || !String(v.body ?? '').trim()) return 'العنوان والنص مطلوبين'
  if (String(v.title).length > 120 || String(v.body).length > 500) return 'العنوان حتى 120 حرف والنص حتى 500'
  if (v.image_url && !String(v.image_url).startsWith('https://')) return 'رابط الصورة يجب أن يبدأ بـ https://'
  if (v.deep_link && !String(v.deep_link).startsWith('enjaz://')) return 'الرابط الداخلي يجب أن يبدأ بـ enjaz://'
  if (v.audience === 'stage' && !v.target_stage_ids?.length) return 'اختر مرحلة'
  if (v.audience === 'grade' && !v.target_grade_ids?.length) return 'اختر صفاً'
  if (v.audience === 'branch' && !v.target_branch_ids?.length) return 'اختر فرعاً'
  if (v.audience === 'user' && !/^[0-9a-f-]{36}$/i.test(v.target_user_id ?? '')) return 'معرّف الطالب غير صالح'
  return null
}

export function NotificationsPage() {
  const fields: FieldDef[] = [
    { key: 'title', label: t.title, type: 'text', required: true, inTable: true, hint: 'مثال: هلا بيك! نزلنا إلك أسئلة جديدة بمادة الرياضيات.' },
    { key: 'body', label: t.body, type: 'textarea', required: true, inTable: true },
    { key: 'image_url', label: t.imageUrl, type: 'url' },
    { key: 'deep_link', label: t.deepLink, type: 'text', hint: 'enjaz://library أو enjaz://quiz ...' },
    { key: 'category', label: t.notifCategory, type: 'select', required: true, default: 'announcements', options: [
      { value: 'announcements', label: 'إعلانات' }, { value: 'motivation', label: 'تحفيز' }, { value: 'study', label: 'دراسة' }, { value: 'exams', label: 'امتحانات' }] },
    { key: 'audience', label: t.audience, type: 'select', required: true, default: 'all', inTable: true, options: [
      { value: 'all', label: t.audienceAll }, { value: 'stage', label: t.audienceStage }, { value: 'grade', label: t.audienceGrade },
      { value: 'branch', label: t.audienceBranch }, { value: 'user', label: t.audienceUser }] },
    { key: 'target_stage_ids', label: t.targetStages, type: 'refMulti', ref: { table: 'academic_stages', label: 'name_ar' }, default: [], showIf: (v) => v.audience === 'stage' },
    { key: 'target_grade_ids', label: t.targetGrades, type: 'refMulti', ref: { table: 'grades', label: 'name_ar' }, default: [], showIf: (v) => v.audience === 'grade' },
    { key: 'target_branch_ids', label: t.targetBranches, type: 'refMulti', ref: { table: 'academic_branches', label: 'name_ar' }, default: [], showIf: (v) => v.audience === 'branch' },
    { key: 'target_user_id', label: t.userId, type: 'text', showIf: (v) => v.audience === 'user' },
    { key: 'status', label: t.status, type: 'select', required: true, default: 'draft', inTable: true, options: [
      { value: 'draft', label: t.saveDraft }, { value: 'scheduled', label: `${t.schedule} / ${t.sendNow}` }] },
    { key: 'scheduled_at', label: `${t.scheduledAt} (فارغ = هسه)`, type: 'datetime', inTable: true, showIf: (v) => v.status === 'scheduled' },
    { key: 'total_recipients', label: t.recipients, type: 'number', inTable: true, showIf: () => false },
    { key: 'success_count', label: t.delivered, type: 'number', inTable: true, showIf: () => false },
    { key: 'sent_at', label: t.sent, type: 'datetime', inTable: true, showIf: () => false },
  ]
  return (
    <CrudPage config={{
      table: 'notification_campaigns', title: t.notifications, fields,
      validate: (v) => {
        const e = validateCampaign(v)
        if (e) return e
        if (v.status === 'scheduled' && !v.scheduled_at) v.scheduled_at = new Date().toISOString()
        return null
      },
      extraActions: (r, reload) => (r.status === 'scheduled' || r.status === 'failed') ? (
        <Button variant="hot" onClick={async () => {
          const { error } = await db().functions.invoke('send-notifications', { body: { campaign_id: r.id } })
          if (error) toast(error.message, true)
          else toast(t.sent)
          reload()
        }}>{t.sendNow}</Button>
      ) : null,
    }} />
  )
}
