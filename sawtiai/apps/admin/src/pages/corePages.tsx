import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { backendConfigured, db, type Row } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { t } from '../lib/strings'
import { Badge, Button, Card, Field, PageHeader, fmtDate, toast } from '../components/ui'
import { useRefs } from '../components/CrudPage'

// ---------------------------------------------------------------------------
// Login (no public registration: admins are provisioned in the database)
// ---------------------------------------------------------------------------
export function LoginPage() {
  const { signIn, denied } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const err = await signIn(email.trim(), password)
    setBusy(false)
    if (err) setError(t.loginFailed)
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <div className="mb-6 text-center">
          <img src="./favicon.svg" alt="" className="mx-auto mb-3 h-16 w-16" />
          <h1 className="text-3xl font-black">{t.appName}</h1>
          <p className="text-muted">{t.dashboard} — {t.slogan}</p>
        </div>
        {!backendConfigured ? (
          <p className="rounded-2xl bg-warning/15 p-4 text-sm text-warning">{t.backendMissing}</p>
        ) : (
          <form onSubmit={submit} className="space-y-4">
            <Field label={t.email}><input type="email" dir="ltr" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
            <Field label={t.password}><input type="password" dir="ltr" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} /></Field>
            {(error || denied) && <p className="text-sm text-danger" role="alert">{denied ? t.notAdmin : error}</p>}
            <Button type="submit" busy={busy} className="w-full">{t.signIn}</Button>
          </form>
        )}
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------
export function OverviewPage() {
  const [d, setD] = useState<Row | null>(null)
  useEffect(() => {
    db().rpc('admin_overview').then(({ data, error }) => (error ? toast(error.message, true) : setD(data as Row)))
  }, [])
  if (!d) return <p className="text-muted">{t.loading}</p>
  const stats: [string, unknown][] = [
    [t.studentsTotal, d.students_total], [t.studentsActive, d.students_active_7d], [t.suspended, d.students_suspended],
    [t.questionsTotal, d.questions_total], [t.questionsLive, d.questions_live], [t.filesLive, d.files_live],
    [t.announcementsTotal, d.announcements_total], [t.campaignsTotal, d.campaigns_total],
  ]
  return (
    <div>
      <PageHeader title={t.overview} />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        {stats.map(([label, v]) => (
          <Card key={label} className="text-center">
            <p className="text-3xl font-black">{String(v ?? 0)}</p>
            <p className="text-sm text-muted">{label}</p>
          </Card>
        ))}
      </div>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <Card>
          <h2 className="mb-3 font-bold">{t.byGrade}</h2>
          {(d.by_grade as Row[]).map((g) => <Bar key={g.grade_id} label={g.name} value={g.count} max={Math.max(1, ...(d.by_grade as Row[]).map((x) => x.count))} />)}
        </Card>
        <Card>
          <h2 className="mb-3 font-bold">{t.byBranch}</h2>
          {(d.by_branch as Row[]).map((b) => <Bar key={b.branch_id} label={`${b.grade} — ${b.name}`} value={b.count} max={Math.max(1, ...(d.by_branch as Row[]).map((x) => x.count))} />)}
        </Card>
      </div>
      <Card className="mt-6">
        <h2 className="mb-3 font-bold">{t.recentActions}</h2>
        <ActivityTable rows={d.recent_actions as Row[]} />
      </Card>
    </div>
  )
}

function Bar({ label, value, max }: { label: string; value: number; max: number }) {
  return (
    <div className="mb-2">
      <div className="flex justify-between text-sm"><span>{label}</span><span className="text-muted">{value}</span></div>
      <div className="h-2.5 rounded-full bg-white/10"><div className="h-2.5 rounded-full bg-gradient-to-l from-success to-cyan" style={{ width: `${(value / max) * 100}%` }} /></div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Students (server-side function returns only the minimum necessary data)
// ---------------------------------------------------------------------------
export function StudentsPage() {
  const { role } = useAuth()
  const refs = useRefs(STUDENT_REF_FIELDS)
  const [rows, setRows] = useState<Row[]>([])
  const [q, setQ] = useState('')
  const [grade, setGrade] = useState('')
  const [branch, setBranch] = useState('')
  const [page, setPage] = useState(0)
  const load = useCallback(async () => {
    const { data, error } = await db().rpc('admin_list_students', {
      p_search: q || null, p_grade: grade || null, p_branch: branch || null, p_limit: 50, p_offset: page * 50,
    })
    if (error) toast(error.message, true)
    setRows((data as Row[]) ?? [])
  }, [q, grade, branch, page])
  useEffect(() => { void load() }, [load])

  const setStatus = async (r: Row, status: 'active' | 'suspended') => {
    let reason: string | null = null
    if (status === 'suspended') {
      reason = prompt(t.suspendReason)
      if (!reason) return
    }
    const { error } = await db().rpc('admin_set_student_status', { p_user: r.id, p_status: status, p_reason: reason })
    if (error) return toast(error.message, true)
    toast(t.saved)
    void load()
  }

  const total = Number(rows[0]?.total ?? 0)
  return (
    <div>
      <PageHeader title={`${t.students} (${total})`} />
      <Card>
        <div className="mb-4 grid gap-3 md:grid-cols-3">
          <input placeholder={t.search} value={q} onChange={(e) => { setPage(0); setQ(e.target.value) }} />
          <select value={grade} onChange={(e) => { setPage(0); setGrade(e.target.value); setBranch('') }}>
            <option value="">{t.grade}: {t.all}</option>
            {(refs.grades ?? []).map((g) => <option key={g.id} value={g.id}>{g.name_ar}</option>)}
          </select>
          <select value={branch} onChange={(e) => { setPage(0); setBranch(e.target.value) }}>
            <option value="">{t.branch}: {t.all}</option>
            {(refs.academic_branches ?? []).filter((b) => !grade || b.grade_id === grade).map((b) => <option key={b.id} value={b.id}>{b.name_ar}</option>)}
          </select>
        </div>
        <div className="overflow-x-auto">
          <table>
            <thead><tr><th>الاسم</th><th>{t.email}</th><th>{t.grade}</th><th>{t.branch}</th><th>المحافظة</th><th>{t.registered}</th><th>{t.lastSeen}</th><th>{t.status}</th><th /></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>{r.display_name || '—'}</td>
                  <td dir="ltr" className="text-start">{r.email || '—'}</td>
                  <td>{r.grade_name || '—'}</td>
                  <td>{r.branch_name || '—'}</td>
                  <td>{r.governorate || '—'}</td>
                  <td>{fmtDate(r.created_at)}</td>
                  <td>{fmtDate(r.last_seen_at)}</td>
                  <td>{r.status === 'suspended' ? <Badge color="danger">{t.suspended}</Badge> : r.status === 'deletion_requested' ? <Badge color="warning">طلب حذف</Badge> : <Badge color="success">{t.active}</Badge>}</td>
                  <td>
                    {role !== 'editor' && (r.status === 'suspended'
                      ? <Button variant="ghost" onClick={() => setStatus(r, 'active')}>{t.restore}</Button>
                      : <Button variant="danger" onClick={() => setStatus(r, 'suspended')}>{t.suspend}</Button>)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mt-4 flex gap-2">
          <Button variant="ghost" disabled={page === 0} onClick={() => setPage(page - 1)}>‹</Button>
          <span className="px-2 py-2 text-sm text-muted">{page + 1}</span>
          <Button variant="ghost" disabled={(page + 1) * 50 >= total} onClick={() => setPage(page + 1)}>›</Button>
        </div>
      </Card>
    </div>
  )
}
const STUDENT_REF_FIELDS = [
  { key: 'g', label: '', type: 'ref' as const, ref: { table: 'grades', label: 'name_ar' } },
  { key: 'b', label: '', type: 'ref' as const, ref: { table: 'academic_branches', label: 'name_ar' } },
]

// ---------------------------------------------------------------------------
// Activity log (append-only, written by database triggers)
// ---------------------------------------------------------------------------
function ActivityTable({ rows }: { rows: Row[] }) {
  return (
    <div className="overflow-x-auto">
      <table>
        <thead><tr><th>{t.time}</th><th>{t.admin}</th><th>{t.action}</th><th>{t.entity}</th></tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className="whitespace-nowrap">{fmtDate(r.created_at)}</td>
              <td>{r.admin_name || String(r.admin_id ?? '').slice(0, 8)}</td>
              <td><Badge color="cyan">{r.action}</Badge></td>
              <td dir="ltr" className="text-start">{r.entity_type}{r.entity_id ? ` · ${String(r.entity_id).slice(0, 8)}` : ''}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function ActivityPage() {
  const [rows, setRows] = useState<Row[]>([])
  const [open, setOpen] = useState<Row | null>(null)
  useEffect(() => {
    db().from('admin_activity_logs').select('*').order('created_at', { ascending: false }).limit(300)
      .then(({ data, error }) => (error ? toast(error.message, true) : setRows(data ?? [])))
  }, [])
  return (
    <div>
      <PageHeader title={t.activity} />
      <Card>
        <div className="overflow-x-auto">
          <table>
            <thead><tr><th>{t.time}</th><th>{t.admin}</th><th>{t.action}</th><th>{t.entity}</th><th /></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="whitespace-nowrap">{fmtDate(r.created_at)}</td>
                  <td dir="ltr">{String(r.admin_id ?? '').slice(0, 8)}</td>
                  <td><Badge color="cyan">{r.action}</Badge></td>
                  <td dir="ltr" className="text-start">{r.entity_type} · {String(r.entity_id ?? '').slice(0, 8)}</td>
                  <td><Button variant="ghost" onClick={() => setOpen(open?.id === r.id ? null : r)}>…</Button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {open && (
          <pre dir="ltr" className="mt-4 max-h-96 overflow-auto rounded-2xl bg-black/30 p-4 text-xs">
            {JSON.stringify({ before: open.before_data, after: open.after_data }, null, 2)}
          </pre>
        )}
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Administrators (super_admin only - enforced by RLS)
// ---------------------------------------------------------------------------
export function AdminsPage() {
  const { role, session } = useAuth()
  const [rows, setRows] = useState<Row[]>([])
  const [email, setEmail] = useState('')
  const [newRole, setNewRole] = useState('editor')
  const load = useCallback(async () => {
    const { data } = await db().from('admin_roles').select('user_id, role, created_at')
    const ids = (data ?? []).map((r) => r.user_id)
    const { data: profs } = ids.length ? await db().from('profiles').select('id, display_name, email').in('id', ids) : { data: [] }
    setRows((data ?? []).map((r) => ({ ...r, ...(profs ?? []).find((p) => p.id === r.user_id) })))
  }, [])
  useEffect(() => { void load() }, [load])
  if (role !== 'super_admin') return <Card><p className="text-muted">{t.superOnly}</p></Card>

  const add = async () => {
    const { data: p } = await db().from('profiles').select('id').eq('email', email.trim().toLowerCase()).maybeSingle()
    if (!p) return toast('ما لگينا حساب بهذا البريد. لازم يسجل دخول مرة وحدة أولاً.', true)
    const { error } = await db().from('admin_roles').insert({ user_id: p.id, role: newRole, granted_by: session?.user.id })
    if (error) return toast(error.message, true)
    setEmail('')
    toast(t.saved)
    void load()
  }
  const remove = async (r: Row) => {
    if (r.user_id === session?.user.id || !confirm(t.confirmDelete)) return
    const { error } = await db().from('admin_roles').delete().eq('user_id', r.user_id)
    if (error) return toast(error.message, true)
    void load()
  }
  return (
    <div>
      <PageHeader title={t.admins} />
      <Card className="mb-4">
        <p className="mb-3 text-sm text-muted">{t.addAdmin}</p>
        <div className="flex flex-wrap gap-2">
          <input dir="ltr" placeholder={t.email} value={email} onChange={(e) => setEmail(e.target.value)} className="max-w-xs" />
          <select value={newRole} onChange={(e) => setNewRole(e.target.value)} className="max-w-40">
            <option value="editor">editor — محرر محتوى</option>
            <option value="admin">admin — مدير</option>
            <option value="super_admin">super_admin — مشرف رئيسي</option>
          </select>
          <Button onClick={add}>{t.add}</Button>
        </div>
      </Card>
      <Card>
        <table>
          <thead><tr><th>الاسم</th><th>{t.email}</th><th>{t.role}</th><th>{t.registered}</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.user_id}>
                <td>{r.display_name || '—'}</td>
                <td dir="ltr" className="text-start">{r.email}</td>
                <td><Badge color="violet">{r.role}</Badge></td>
                <td>{fmtDate(r.created_at)}</td>
                <td>{r.user_id !== session?.user.id && <Button variant="danger" onClick={() => remove(r)}>{t.delete}</Button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  )
}
