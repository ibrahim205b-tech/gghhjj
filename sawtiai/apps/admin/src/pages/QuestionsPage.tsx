import { useCallback, useEffect, useMemo, useState } from 'react'
import { db, publicUrl, type Row } from '../lib/supabase'
import { t } from '../lib/strings'
import { csvTemplate, jsonTemplate, parseImport, type KnownIds, type ValidatedRow } from '../lib/questionImport'
import { Badge, Button, Card, Field, Modal, PageHeader, StatusBadge, toast } from '../components/ui'
import { FieldInput, useRefs, type FieldDef } from '../components/CrudPage'

const QFIELDS: FieldDef[] = [
  { key: 'grade_id', label: t.grade, type: 'ref', ref: { table: 'grades', label: 'name_ar' }, required: true },
  { key: 'branch_id', label: `${t.branch} (فارغ = الكل)`, type: 'ref', ref: { table: 'academic_branches', label: 'name_ar', filter: { grade_id: '$grade_id' } } },
  { key: 'year_id', label: t.year, type: 'ref', ref: { table: 'academic_years', label: 'label' } },
  { key: 'subject_id', label: t.subject, type: 'ref', ref: { table: 'subjects', label: 'name_ar', filter: { grade_id: '$grade_id' } }, required: true },
  { key: 'chapter_id', label: t.chapter, type: 'ref', ref: { table: 'chapters', label: 'title', filter: { subject_id: '$subject_id' } } },
  { key: 'topic_id', label: t.topic, type: 'ref', ref: { table: 'topics', label: 'title', filter: { chapter_id: '$chapter_id' } } },
  { key: 'image_path', label: t.image, type: 'image' },
  { key: 'difficulty', label: t.difficulty, type: 'select', required: true, options: [{ value: '1', label: 'سهل' }, { value: '2', label: 'متوسط' }, { value: '3', label: 'صعب' }] },
  { key: 'source_type', label: t.sourceType, type: 'select', required: true, options: [
    { value: 'practice', label: t.practice }, { value: 'textbook', label: t.textbook },
    { value: 'teacher', label: t.teacher }, { value: 'official_ministerial', label: t.officialMinisterial }] },
  { key: 'source', label: t.source, type: 'text' },
  { key: 'question_year', label: t.questionYear, type: 'number' },
  { key: 'publish_at', label: t.publishAt, type: 'datetime' },
  { key: 'expires_at', label: t.expiresAt, type: 'datetime' },
]

interface Opt { id?: string; option_text: string; is_correct: boolean }

function emptyQuestion(): Row {
  return { question_type: 'multiple_choice', difficulty: '2', source_type: 'practice', status: 'draft',
    options: [{ option_text: '', is_correct: true }, { option_text: '', is_correct: false }] }
}

export function validateQuestion(q: Row): string | null {
  if (!q.grade_id || !q.subject_id) return 'اختر الصف والمادة'
  if (!String(q.question_text ?? '').trim()) return 'اكتب نص السؤال'
  const opts = (q.options as Opt[]).filter((o) => o.option_text.trim())
  if (q.question_type === 'short_answer') {
    if (!String(q.answer_text ?? '').trim()) return 'اكتب الجواب المقبول'
  } else {
    if (opts.length < 2) return 'أضف خيارين على الأقل'
    if (q.question_type === 'true_false' && opts.length !== 2) return 'صح/خطأ يحتاج خيارين بالضبط'
    if (opts.filter((o) => o.is_correct).length !== 1) return 'حدد خياراً صحيحاً واحداً'
  }
  if (q.source_type === 'official_ministerial' && (!q.source || !q.question_year)) {
    return 'السؤال الوزاري يحتاج مصدر وسنة — لا تُنسب أسئلة للوزارة بدون دليل'
  }
  if (q.status === 'scheduled' && !q.publish_at) return 'حدد موعد النشر'
  return null
}

export function QuestionsPage() {
  const refs = useRefs(QFIELDS)
  const [rows, setRows] = useState<Row[]>([])
  const [filters, setFilters] = useState<Row>({ grade_id: '', subject_id: '', status: '', q: '' })
  const [editing, setEditing] = useState<Row | null>(null)
  const [preview, setPreview] = useState<Row | null>(null)
  const [importOpen, setImportOpen] = useState(false)
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    let q = db().from('questions').select('*, question_options(*)').is('deleted_at', null)
    if (filters.grade_id) q = q.eq('grade_id', filters.grade_id)
    if (filters.subject_id) q = q.eq('subject_id', filters.subject_id)
    if (filters.status) q = q.eq('status', filters.status)
    if (filters.q) q = q.ilike('question_text', `%${filters.q}%`)
    const { data, error } = await q.order('created_at', { ascending: false }).limit(300)
    if (error) toast(error.message, true)
    setRows(data ?? [])
  }, [filters])
  useEffect(() => { void load() }, [load])

  const open = (r?: Row, duplicate = false) => {
    if (!r) return setEditing(emptyQuestion())
    const opts = ((r.question_options as Row[]) ?? []).sort((a, b) => a.sort_order - b.sort_order)
      .map((o) => ({ id: duplicate ? undefined : o.id, option_text: o.option_text, is_correct: o.is_correct }))
    const copy: Row = { ...r, difficulty: String(r.difficulty), options: opts }
    delete copy.question_options
    if (duplicate) {
      delete copy.id
      copy.status = 'draft'
    }
    setEditing(copy)
  }

  const save = async () => {
    if (!editing) return
    const err = validateQuestion(editing)
    if (err) return toast(err, true)
    setSaving(true)
    const payload: Row = {}
    for (const k of ['id', 'grade_id', 'branch_id', 'year_id', 'subject_id', 'chapter_id', 'topic_id', 'question_type', 'question_text',
      'image_path', 'answer_text', 'explanation', 'difficulty', 'source', 'source_type', 'question_year', 'status', 'publish_at', 'expires_at']) {
      if (editing[k] !== undefined) payload[k] = editing[k] === '' ? null : editing[k]
    }
    payload.difficulty = Number(payload.difficulty)
    if (payload.question_type !== 'short_answer') payload.answer_text = null
    const { data, error } = await db().from('questions').upsert(payload).select('id').single()
    if (error) {
      setSaving(false)
      return toast(error.message, true)
    }
    const qid = data.id
    // Replace options atomically from the dashboard's point of view.
    await db().from('question_options').delete().eq('question_id', qid)
    if (payload.question_type !== 'short_answer') {
      const opts = (editing.options as Opt[]).filter((o) => o.option_text.trim())
        .map((o, i) => ({ question_id: qid, option_text: o.option_text.trim(), is_correct: o.is_correct, sort_order: i + 1 }))
      const { error: e2 } = await db().from('question_options').insert(opts)
      if (e2) {
        setSaving(false)
        return toast(e2.message, true)
      }
    }
    setSaving(false)
    toast(t.saved)
    setEditing(null)
    void load()
  }

  const setStatus = async (r: Row, status: string) => {
    const { error } = await db().from('questions').update({ status, publish_at: status === 'published' ? new Date().toISOString() : r.publish_at }).eq('id', r.id)
    if (error) return toast(error.message, true)
    void load()
  }

  const remove = async (r: Row) => {
    if (!confirm(t.confirmDelete)) return
    const { error } = await db().from('questions').update({ deleted_at: new Date().toISOString() }).eq('id', r.id)
    if (error) return toast(error.message, true)
    void load()
  }

  const nameOf = (table: string, id: string, key = 'name_ar') => refs[table]?.find((x) => x.id === id)?.[key] ?? '—'

  return (
    <div>
      <PageHeader title={t.questions} actions={<>
        <Button variant="ghost" onClick={() => setImportOpen(true)}>{t.importQuestions}</Button>
        <Button onClick={() => open()}>+ {t.add}</Button>
      </>} />
      <Card>
        <div className="mb-4 grid gap-3 md:grid-cols-4">
          <input placeholder={t.search} value={filters.q} onChange={(e) => setFilters({ ...filters, q: e.target.value })} />
          <select value={filters.grade_id} onChange={(e) => setFilters({ ...filters, grade_id: e.target.value, subject_id: '' })}>
            <option value="">{t.grade}: {t.all}</option>
            {(refs.grades ?? []).map((g) => <option key={g.id} value={g.id}>{g.name_ar}</option>)}
          </select>
          <select value={filters.subject_id} onChange={(e) => setFilters({ ...filters, subject_id: e.target.value })}>
            <option value="">{t.subject}: {t.all}</option>
            {(refs.subjects ?? []).filter((s) => !filters.grade_id || s.grade_id === filters.grade_id).map((s) => <option key={s.id} value={s.id}>{s.name_ar}</option>)}
          </select>
          <select value={filters.status} onChange={(e) => setFilters({ ...filters, status: e.target.value })}>
            <option value="">{t.status}: {t.all}</option>
            {['draft', 'scheduled', 'published', 'expired', 'archived'].map((s) => <option key={s} value={s}>{t[s as 'draft']}</option>)}
          </select>
        </div>
        <div className="overflow-x-auto">
          <table>
            <thead><tr><th>{t.questionText}</th><th>{t.grade}</th><th>{t.subject}</th><th>{t.type}</th><th>{t.source}</th><th>{t.status}</th><th>{t.actions}</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="max-w-md">{String(r.question_text).slice(0, 120)}</td>
                  <td>{nameOf('grades', r.grade_id)}</td>
                  <td>{nameOf('subjects', r.subject_id)}</td>
                  <td>{{ multiple_choice: t.mcq, true_false: t.trueFalse, short_answer: t.shortAnswer }[r.question_type as string]}</td>
                  <td>{r.source_type === 'official_ministerial' ? <Badge color="cyan">{t.officialMinisterial} {r.question_year}</Badge> : <Badge color="muted">{t[r.source_type as 'practice']}</Badge>}</td>
                  <td><StatusBadge status={r.status} /></td>
                  <td className="whitespace-nowrap">
                    <div className="flex flex-wrap gap-1">
                      <Button variant="ghost" onClick={() => open(r)}>{t.edit}</Button>
                      <Button variant="ghost" onClick={() => setPreview(r)}>{t.preview}</Button>
                      <Button variant="ghost" onClick={() => open(r, true)}>{t.duplicate}</Button>
                      {r.status !== 'published'
                        ? <Button variant="ghost" onClick={() => setStatus(r, 'published')}>{t.publishNow}</Button>
                        : <Button variant="ghost" onClick={() => setStatus(r, 'draft')}>{t.unpublish}</Button>}
                      <Button variant="danger" onClick={() => remove(r)}>{t.delete}</Button>
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
          <div className="space-y-4">
            <div className="grid gap-4 md:grid-cols-3">
              {QFIELDS.slice(0, 6).map((f) => (
                <Field key={f.key} label={f.label + (f.required ? ' *' : '')}>
                  <FieldInput f={f} value={editing[f.key]} values={editing} refs={refs} onChange={(v) => setEditing({ ...editing, [f.key]: v })} />
                </Field>
              ))}
            </div>
            <Field label={`${t.questionType} *`}>
              <select value={editing.question_type} onChange={(e) => {
                const type = e.target.value
                setEditing({ ...editing, question_type: type,
                  options: type === 'true_false' ? [{ option_text: 'صح', is_correct: true }, { option_text: 'خطأ', is_correct: false }] : editing.options })
              }}>
                <option value="multiple_choice">{t.mcq}</option>
                <option value="true_false">{t.trueFalse}</option>
                <option value="short_answer">{t.shortAnswer}</option>
              </select>
            </Field>
            <Field label={`${t.questionText} *`} hint="يُعرض للطالب كما هو تماماً — لا تُعدِّل صياغة الأسئلة الرسمية.">
              <textarea rows={4} value={editing.question_text ?? ''} onChange={(e) => setEditing({ ...editing, question_text: e.target.value })} />
            </Field>
            {editing.question_type === 'short_answer' ? (
              <Field label={`${t.answerText} *`}>
                <input value={editing.answer_text ?? ''} onChange={(e) => setEditing({ ...editing, answer_text: e.target.value })} />
              </Field>
            ) : (
              <div>
                <p className="mb-2 text-sm text-muted">{t.options}</p>
                {(editing.options as Opt[]).map((o, i) => (
                  <div key={i} className="mb-2 flex items-center gap-2">
                    <input type="radio" className="!w-auto" name="correct" checked={o.is_correct} aria-label={t.correct}
                      onChange={() => setEditing({ ...editing, options: (editing.options as Opt[]).map((x, j) => ({ ...x, is_correct: j === i })) })} />
                    <input value={o.option_text} onChange={(e) => setEditing({ ...editing, options: (editing.options as Opt[]).map((x, j) => (j === i ? { ...x, option_text: e.target.value } : x)) })} />
                    {editing.question_type === 'multiple_choice' && (editing.options as Opt[]).length > 2 && (
                      <Button variant="ghost" onClick={() => setEditing({ ...editing, options: (editing.options as Opt[]).filter((_, j) => j !== i) })}>×</Button>
                    )}
                  </div>
                ))}
                {editing.question_type === 'multiple_choice' && (editing.options as Opt[]).length < 6 && (
                  <Button variant="ghost" onClick={() => setEditing({ ...editing, options: [...(editing.options as Opt[]), { option_text: '', is_correct: false }] })}>+ {t.addOption}</Button>
                )}
              </div>
            )}
            <Field label={t.explanation}>
              <textarea rows={3} value={editing.explanation ?? ''} onChange={(e) => setEditing({ ...editing, explanation: e.target.value })} />
            </Field>
            <div className="grid gap-4 md:grid-cols-3">
              {QFIELDS.slice(6).map((f) => (
                <Field key={f.key} label={f.label + (f.required ? ' *' : '')}>
                  <FieldInput f={f} value={editing[f.key]} values={editing} refs={refs} onChange={(v) => setEditing({ ...editing, [f.key]: v })} />
                </Field>
              ))}
              <Field label={t.status}>
                <select value={editing.status} onChange={(e) => setEditing({ ...editing, status: e.target.value })}>
                  {['draft', 'scheduled', 'published', 'archived'].map((s) => <option key={s} value={s}>{t[s as 'draft']}</option>)}
                </select>
              </Field>
            </div>
            <div className="flex gap-2">
              <Button onClick={save} busy={saving}>{t.save}</Button>
              <Button variant="ghost" onClick={() => setPreview({ ...editing, question_options: editing.options })}>{t.preview}</Button>
              <Button variant="ghost" onClick={() => setEditing(null)}>{t.cancel}</Button>
            </div>
          </div>
        )}
      </Modal>

      <Modal open={!!preview} title={t.preview} onClose={() => setPreview(null)}>
        {preview && <QuestionPreview q={preview} />}
      </Modal>
      <ImportModal open={importOpen} onClose={() => setImportOpen(false)} onDone={load} refs={refs} />
    </div>
  )
}

/** What the student will see (mirrors the app's quiz card). */
export function QuestionPreview({ q }: { q: Row }) {
  const img = publicUrl(q.image_path)
  const opts = ((q.question_options as Opt[]) ?? []).filter((o) => o.option_text)
  return (
    <div className="mx-auto max-w-sm rounded-3xl border border-white/10 bg-navy p-5">
      <Badge color={q.source_type === 'official_ministerial' ? 'cyan' : 'violet'}>
        {q.source_type === 'official_ministerial' ? `سؤال وزاري ${q.question_year ?? ''}` : 'سؤال تدريبي'}
      </Badge>
      <p className="mt-3 text-lg leading-8">{q.question_text}</p>
      {img && <img src={img} alt="" className="mt-3 rounded-2xl" />}
      <div className="mt-4 space-y-2">
        {q.question_type === 'short_answer'
          ? <div className="rounded-2xl border border-white/10 p-3 text-muted">اكتب جوابك هنا</div>
          : opts.map((o, i) => <div key={i} className={`rounded-2xl border p-3 ${o.is_correct ? 'border-success' : 'border-white/10'}`}>{o.option_text}</div>)}
      </div>
      {q.explanation && <p className="mt-3 text-sm text-muted">الشرح: {q.explanation}</p>}
    </div>
  )
}

function download(name: string, text: string, type: string) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob(['﻿' + text], { type }))
  a.download = name
  a.click()
  URL.revokeObjectURL(a.href)
}

function ImportModal({ open, onClose, onDone, refs }: { open: boolean; onClose: () => void; onDone: () => void; refs: Record<string, Row[]> }) {
  const [result, setResult] = useState<ValidatedRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const known: KnownIds = useMemo(() => ({
    grades: new Set((refs.grades ?? []).map((g) => g.id)),
    branches: new Map((refs.academic_branches ?? []).map((b) => [b.id, b.grade_id])),
    subjects: new Map((refs.subjects ?? []).map((s) => [s.id, s.grade_id])),
    chapters: new Map((refs.chapters ?? []).map((c) => [c.id, c.subject_id])),
  }), [refs])
  const valid = result?.filter((r) => r.row) ?? []
  const invalid = result?.filter((r) => !r.row) ?? []

  const importNow = async () => {
    setBusy(true)
    let n = 0
    for (const v of valid) {
      const r = v.row!
      const { data, error } = await db().from('questions').insert({
        grade_id: r.grade_id, branch_id: r.branch_id ?? null, year_id: r.year_id ?? null, subject_id: r.subject_id,
        chapter_id: r.chapter_id ?? null, topic_id: r.topic_id ?? null, question_type: r.question_type,
        question_text: r.question_text, answer_text: r.question_type === 'short_answer' ? r.answer_text : null,
        explanation: r.explanation ?? null, difficulty: r.difficulty ?? 2, source: r.source ?? null,
        source_type: r.source_type ?? 'practice', question_year: r.question_year ?? null, status: 'draft',
      }).select('id').single()
      if (error) {
        toast(`سطر ${v.line}: ${error.message}`, true)
        continue
      }
      if (r.question_type !== 'short_answer') {
        await db().from('question_options').insert((r.options ?? []).map((o, i) => ({
          question_id: data.id, option_text: o, is_correct: i + 1 === r.correct_option, sort_order: i + 1,
        })))
      }
      n++
    }
    setBusy(false)
    toast(`${t.imported}: ${n} (كمسودات — راجعها وانشرها)`)
    setResult(null)
    onDone()
    onClose()
  }

  return (
    <Modal open={open} title={t.importQuestions} onClose={onClose} wide>
      <p className="mb-3 text-sm text-muted">{t.importHint}</p>
      <div className="mb-4 flex flex-wrap gap-2">
        <Button variant="ghost" onClick={() => download('enjaz-questions-template.csv', csvTemplate(), 'text/csv')}>{t.downloadCsvTemplate}</Button>
        <Button variant="ghost" onClick={() => download('enjaz-questions-template.json', jsonTemplate(), 'application/json')}>{t.downloadJsonTemplate}</Button>
        <input type="file" accept=".csv,.json" className="!w-auto" onChange={async (e) => {
          const f = e.target.files?.[0]
          if (!f) return
          if (f.size > 5 * 1024 * 1024) return toast(t.fileTooLarge, true)
          setResult(parseImport(await f.text(), f.name, known))
        }} />
      </div>
      {result && (
        <div>
          <div className="mb-3 flex gap-3">
            <Badge color="success">{t.importValid}: {valid.length}</Badge>
            <Badge color="danger">{t.importInvalid}: {invalid.length}</Badge>
          </div>
          {invalid.length > 0 && (
            <ul className="mb-3 max-h-60 overflow-auto rounded-2xl bg-black/30 p-3 text-sm">
              {invalid.map((r) => <li key={r.line} className="mb-1"><b>سطر {r.line}:</b> {r.errors.join(' — ')}</li>)}
            </ul>
          )}
          <Button onClick={importNow} busy={busy} disabled={!valid.length}>{t.importNow}</Button>
        </div>
      )}
    </Modal>
  )
}
