import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { db, publicUrl, uploadFile, type Row } from '../lib/supabase'
import { t } from '../lib/strings'
import { Badge, Button, Card, Field, Modal, PageHeader, StatusBadge, fmtDate, fromLocalInput, toLocalInput, toast } from './ui'

export type FieldType =
  | 'text' | 'textarea' | 'number' | 'bool' | 'select' | 'ref' | 'refMulti' | 'date' | 'datetime'
  | 'color' | 'image' | 'url' | 'json'

export interface FieldDef {
  key: string
  label: string
  type: FieldType
  required?: boolean
  options?: { value: string; label: string }[]
  ref?: { table: string; label: string; filter?: Record<string, unknown> }
  inTable?: boolean
  default?: unknown
  hint?: string
  /** Hide the field unless the predicate holds for the current form values. */
  showIf?: (v: Row) => boolean
}

export interface CrudConfig {
  table: string
  title: string
  fields: FieldDef[]
  orderBy?: { column: string; ascending?: boolean }
  softDelete?: boolean
  sortable?: boolean
  publishable?: boolean
  activatable?: boolean
  baseFilter?: Record<string, unknown>
  defaults?: Row
  searchKeys?: string[]
  primaryKey?: string
  /** Final validation; return an Arabic error message to block saving. */
  validate?: (v: Row) => string | null
  extraActions?: (row: Row, reload: () => void) => ReactNode
  preview?: (v: Row) => ReactNode
}

type RefCache = Record<string, Row[]>

export function useRefs(fields: FieldDef[]) {
  const [refs, setRefs] = useState<RefCache>({})
  useEffect(() => {
    const tables = [...new Set(fields.filter((f) => f.ref).map((f) => f.ref!.table))]
    Promise.all(
      tables.map(async (tb) => {
        const { data } = await db().from(tb).select('*').is('deleted_at', null).order('sort_order', { ascending: true }).limit(2000)
          .then((r) => (r.error ? db().from(tb).select('*').limit(2000) : r))
        return [tb, data ?? []] as const
      }),
    ).then((entries) => setRefs(Object.fromEntries(entries)))
  }, [fields])
  return refs
}

export function refLabel(refs: RefCache, f: FieldDef, id: unknown): string {
  if (id === null || id === undefined || id === '') return '—'
  const r = refs[f.ref!.table]?.find((x) => x.id === id)
  return r ? String(r[f.ref!.label]) : String(id).slice(0, 8)
}

export function FieldInput({ f, value, onChange, refs, values }: { f: FieldDef; value: unknown; onChange: (v: unknown) => void; refs: RefCache; values: Row }) {
  const [uploading, setUploading] = useState(false)
  switch (f.type) {
    case 'textarea':
      return <textarea rows={4} value={(value as string) ?? ''} onChange={(e) => onChange(e.target.value)} />
    case 'number':
      return <input type="number" value={value === null || value === undefined ? '' : String(value)} onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))} />
    case 'bool':
      return (
        <input type="checkbox" className="!w-auto" checked={!!value} onChange={(e) => onChange(e.target.checked)} />
      )
    case 'select':
      return (
        <select value={(value as string) ?? ''} onChange={(e) => onChange(e.target.value || null)}>
          {!f.required && <option value="">—</option>}
          {f.options!.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      )
    case 'ref': {
      const rows = (refs[f.ref!.table] ?? []).filter((r) =>
        Object.entries(f.ref!.filter ?? {}).every(([k, v]) => (typeof v === 'string' && v.startsWith('$') ? r[k] === values[v.slice(1)] : r[k] === v)))
      return (
        <select value={(value as string) ?? ''} onChange={(e) => onChange(e.target.value || null)}>
          <option value="">{f.required ? '— اختر —' : t.all}</option>
          {rows.map((r) => <option key={r.id} value={r.id}>{String(r[f.ref!.label])}</option>)}
        </select>
      )
    }
    case 'refMulti': {
      const sel = new Set<string>((value as string[]) ?? [])
      const rows = refs[f.ref!.table] ?? []
      return (
        <div className="flex flex-wrap gap-2">
          {rows.map((r) => (
            <button type="button" key={r.id}
              onClick={() => { const n = new Set(sel); if (n.has(r.id)) { n.delete(r.id) } else { n.add(r.id) } onChange([...n]) }}
              className={`rounded-full border px-3 py-1 text-xs ${sel.has(r.id) ? 'border-cyan bg-cyan/20' : 'border-white/15'}`}>
              {String(r[f.ref!.label])}
            </button>
          ))}
        </div>
      )
    }
    case 'date':
      return <input type="date" value={(value as string)?.slice(0, 10) ?? ''} onChange={(e) => onChange(e.target.value || null)} />
    case 'datetime':
      return <input type="datetime-local" value={toLocalInput(value as string)} onChange={(e) => onChange(fromLocalInput(e.target.value))} />
    case 'color':
      return <input type="color" className="!h-10 !w-20 !p-1" value={(value as string) ?? '#3DA9FC'} onChange={(e) => onChange(e.target.value.toUpperCase())} />
    case 'json':
      return <textarea rows={4} dir="ltr" value={typeof value === 'string' ? value : JSON.stringify(value ?? null)} onChange={(e) => onChange(e.target.value)} />
    case 'image': {
      const url = publicUrl(value as string)
      return (
        <div className="flex items-center gap-3">
          {url && <img src={url} alt="" className="h-16 w-16 rounded-xl object-cover" />}
          <input type="file" accept="image/jpeg,image/png,image/webp" className="!w-auto" disabled={uploading}
            onChange={async (e) => {
              const file = e.target.files?.[0]
              if (!file) return
              if (file.size > 10 * 1024 * 1024) return toast(t.fileTooLarge, true)
              setUploading(true)
              try { onChange(await uploadFile('content', file, 'images')) } catch (err) { toast(String((err as Error).message), true) } finally { setUploading(false) }
            }} />
          {value ? <Button variant="ghost" type="button" onClick={() => onChange(null)}>{t.delete}</Button> : null}
        </div>
      )
    }
    case 'url':
      return <input type="url" dir="ltr" value={(value as string) ?? ''} onChange={(e) => onChange(e.target.value || null)} />
    default:
      return <input type="text" value={(value as string) ?? ''} onChange={(e) => onChange(e.target.value)} />
  }
}

const publishFields: FieldDef[] = [
  { key: 'status', label: t.status, type: 'select', required: true, inTable: true, default: 'draft', options: [
    { value: 'draft', label: t.draft }, { value: 'scheduled', label: t.scheduled }, { value: 'published', label: t.published },
    { value: 'expired', label: t.expired }, { value: 'archived', label: t.archived }] },
  { key: 'publish_at', label: t.publishAt, type: 'datetime', showIf: (v) => v.status === 'scheduled' },
  { key: 'expires_at', label: t.expiresAt, type: 'datetime' },
]

export function CrudPage({ config }: { config: CrudConfig }) {
  const fields = useMemo(() => [...config.fields, ...(config.publishable ? publishFields : []),
    ...(config.activatable ? [{ key: 'is_active', label: t.active, type: 'bool', default: true, inTable: true } as FieldDef] : [])],
  [config])
  const refs = useRefs(fields)
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(true)
  const [q, setQ] = useState('')
  const [editing, setEditing] = useState<Row | null>(null)
  const [saving, setSaving] = useState(false)
  const pk = config.primaryKey ?? 'id'

  const load = useCallback(async () => {
    setLoading(true)
    let query = db().from(config.table).select('*')
    for (const [k, v] of Object.entries(config.baseFilter ?? {})) query = query.eq(k, v)
    if (config.softDelete) query = query.is('deleted_at', null)
    const ob = config.orderBy ?? (config.sortable ? { column: 'sort_order', ascending: true } : { column: 'created_at', ascending: false })
    const { data, error } = await query.order(ob.column, { ascending: ob.ascending ?? true }).limit(1000)
    if (error) toast(error.message, true)
    setRows(data ?? [])
    setLoading(false)
  }, [config])

  useEffect(() => { void load() }, [load])

  const visible = rows.filter((r) => !q || (config.searchKeys ?? fields.filter((f) => f.type === 'text').map((f) => f.key))
    .some((k) => String(r[k] ?? '').toLowerCase().includes(q.toLowerCase())))

  const startNew = () => {
    const v: Row = { ...(config.defaults ?? {}), ...(config.baseFilter ?? {}) }
    for (const f of fields) if (f.default !== undefined && v[f.key] === undefined) v[f.key] = f.default
    if (config.sortable) v.sort_order = (rows.reduce((m, r) => Math.max(m, Number(r.sort_order ?? 0)), 0) || 0) + 1
    setEditing(v)
  }

  const save = async () => {
    if (!editing) return
    for (const f of fields) {
      if (f.required && (f.showIf?.(editing) ?? true) && (editing[f.key] === undefined || editing[f.key] === null || editing[f.key] === '')) {
        return toast(`${f.label}: ${t.required}`, true)
      }
    }
    if (editing.status === 'scheduled' && !editing.publish_at) return toast(`${t.publishAt}: ${t.required}`, true)
    const err = config.validate?.(editing)
    if (err) return toast(err, true)
    const payload: Row = {}
    for (const f of fields) {
      if (!(f.key in editing)) continue
      let v = editing[f.key]
      if (f.type === 'json' && typeof v === 'string') {
        try { v = JSON.parse(v) } catch { return toast(`${f.label}: JSON`, true) }
      }
      payload[f.key] = v === '' ? null : v
    }
    for (const k of Object.keys(config.baseFilter ?? {})) payload[k] = config.baseFilter![k]
    if (config.sortable) payload.sort_order = editing.sort_order ?? 0
    if (editing[pk]) payload[pk] = editing[pk]
    setSaving(true)
    const { error } = await db().from(config.table).upsert(payload, { onConflict: pk })
    setSaving(false)
    if (error) return toast(error.message, true)
    toast(t.saved)
    setEditing(null)
    void load()
  }

  const remove = async (r: Row) => {
    if (!confirm(t.confirmDelete)) return
    const { error } = config.softDelete
      ? await db().from(config.table).update({ deleted_at: new Date().toISOString() }).eq(pk, r[pk])
      : await db().from(config.table).delete().eq(pk, r[pk])
    if (error) return toast(error.message, true)
    toast(t.deleted)
    void load()
  }

  const move = async (r: Row, dir: -1 | 1) => {
    const i = visible.indexOf(r)
    const other = visible[i + dir]
    if (!other) return
    const a = Number(r.sort_order ?? 0), b = Number(other.sort_order ?? 0)
    await db().from(config.table).update({ sort_order: b === a ? a + dir : b }).eq(pk, r[pk])
    await db().from(config.table).update({ sort_order: a }).eq(pk, other[pk])
    void load()
  }

  const quick = async (r: Row, patch: Row) => {
    const { error } = await db().from(config.table).update(patch).eq(pk, r[pk])
    if (error) return toast(error.message, true)
    void load()
  }

  const tableFields = fields.filter((f) => f.inTable)

  const cell = (f: FieldDef, r: Row): ReactNode => {
    const v = r[f.key]
    if (f.key === 'status') return <StatusBadge status={v} />
    switch (f.type) {
      case 'bool': return v ? <Badge color="success">{t.yes}</Badge> : <Badge color="muted">{t.no}</Badge>
      case 'ref': return refLabel(refs, f, v)
      case 'refMulti': return (v as string[] | null)?.length ? (v as string[]).map((id) => refLabel(refs, f, id)).join('، ') : t.all
      case 'datetime': return fmtDate(v)
      case 'select': return f.options?.find((o) => o.value === v)?.label ?? String(v ?? '—')
      case 'color': return <span className="inline-block h-4 w-4 rounded-full" style={{ background: v }} />
      case 'image': { const u = publicUrl(v); return u ? <img src={u} alt="" className="h-10 w-10 rounded-lg object-cover" /> : '—' }
      default: { const s = String(v ?? '—'); return s.length > 80 ? s.slice(0, 80) + '…' : s }
    }
  }

  return (
    <div>
      <PageHeader title={config.title} actions={<Button onClick={startNew}>+ {t.add}</Button>} />
      <Card>
        <input placeholder={t.search} value={q} onChange={(e) => setQ(e.target.value)} className="mb-4 max-w-sm" />
        {loading ? <p className="text-muted">{t.loading}</p> : (
          <div className="overflow-x-auto">
            <table>
              <thead><tr>{tableFields.map((f) => <th key={f.key}>{f.label}</th>)}<th>{t.actions}</th></tr></thead>
              <tbody>
                {visible.map((r) => (
                  <tr key={String(r[pk])}>
                    {tableFields.map((f) => <td key={f.key}>{cell(f, r)}</td>)}
                    <td className="whitespace-nowrap">
                      <div className="flex flex-wrap gap-1">
                        <Button variant="ghost" onClick={() => setEditing({ ...r })}>{t.edit}</Button>
                        {config.sortable && <>
                          <Button variant="ghost" onClick={() => move(r, -1)} aria-label={t.moveUp}>↑</Button>
                          <Button variant="ghost" onClick={() => move(r, 1)} aria-label={t.moveDown}>↓</Button>
                        </>}
                        {config.activatable && <Button variant="ghost" onClick={() => quick(r, { is_active: !r.is_active })}>{r.is_active ? t.inactive : t.active}</Button>}
                        {config.publishable && r.status !== 'published' && <Button variant="ghost" onClick={() => quick(r, { status: 'published', publish_at: new Date().toISOString() })}>{t.publishNow}</Button>}
                        {config.publishable && r.status === 'published' && <Button variant="ghost" onClick={() => quick(r, { status: 'draft' })}>{t.unpublish}</Button>}
                        {config.extraActions?.(r, load)}
                        <Button variant="danger" onClick={() => remove(r)}>{t.delete}</Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!visible.length && <p className="py-6 text-center text-muted">—</p>}
          </div>
        )}
      </Card>
      <Modal open={!!editing} title={editing?.[pk] ? t.edit : t.add} onClose={() => setEditing(null)} wide>
        {editing && (
          <div className="grid gap-4 md:grid-cols-2">
            {fields.filter((f) => f.showIf?.(editing) ?? true).map((f) => (
              <div key={f.key} className={f.type === 'textarea' || f.type === 'refMulti' || f.type === 'json' ? 'md:col-span-2' : ''}>
                <Field label={f.label + (f.required ? ' *' : '')} hint={f.hint}>
                  <FieldInput f={f} value={editing[f.key]} values={editing} refs={refs} onChange={(v) => setEditing({ ...editing, [f.key]: v })} />
                </Field>
              </div>
            ))}
            {config.preview && <div className="md:col-span-2"><p className="mb-2 text-sm text-muted">{t.preview}</p>{config.preview(editing)}</div>}
            <div className="flex gap-2 md:col-span-2">
              <Button onClick={save} busy={saving}>{t.save}</Button>
              <Button variant="ghost" onClick={() => setEditing(null)}>{t.cancel}</Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
