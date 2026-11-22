import { useEffect, useState, type ReactNode, type ButtonHTMLAttributes } from 'react'
import { t } from '../lib/strings'

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`glass p-5 ${className}`}>{children}</div>
}

type BtnProps = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'brand' | 'hot' | 'ghost' | 'danger'; busy?: boolean }
export function Button({ variant = 'brand', busy, className = '', children, disabled, ...rest }: BtnProps) {
  const v = {
    brand: 'btn-brand text-white',
    hot: 'btn-hot text-white',
    ghost: 'bg-white/5 border border-white/15 hover:bg-white/10',
    danger: 'bg-danger/20 text-danger border border-danger/40 hover:bg-danger/30',
  }[variant]
  return (
    <button
      {...rest}
      disabled={disabled || busy}
      className={`rounded-full px-4 py-2 text-sm font-semibold transition disabled:opacity-50 ${v} ${className}`}
    >
      {busy ? '…' : children}
    </button>
  )
}

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return (
    <label className="block text-sm">
      <span className="mb-1 block text-muted">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-muted">{hint}</span>}
    </label>
  )
}

export function Badge({ children, color = 'cyan' }: { children: ReactNode; color?: 'cyan' | 'success' | 'warning' | 'danger' | 'violet' | 'muted' }) {
  const c = {
    cyan: 'bg-cyan/15 text-cyan',
    success: 'bg-success/15 text-success',
    warning: 'bg-warning/15 text-warning',
    danger: 'bg-danger/15 text-danger',
    violet: 'bg-violet/20 text-violet',
    muted: 'bg-white/10 text-muted',
  }[color]
  return <span className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-bold ${c}`}>{children}</span>
}

export function StatusBadge({ status }: { status?: string }) {
  const map: Record<string, [string, 'muted' | 'warning' | 'success' | 'danger' | 'violet']> = {
    draft: [t.draft, 'muted'],
    scheduled: [t.scheduled, 'warning'],
    published: [t.published, 'success'],
    expired: [t.expired, 'danger'],
    archived: [t.archived, 'violet'],
    sending: [t.sending, 'warning'],
    sent: [t.sent, 'success'],
    failed: [t.failed, 'danger'],
    cancelled: [t.archived, 'muted'],
  }
  const [label, color] = map[status ?? ''] ?? [status ?? '—', 'muted']
  return <Badge color={color}>{label}</Badge>
}

export function Modal({ open, title, onClose, children, wide }: { open: boolean; title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/60 p-4" role="dialog" aria-modal="true" aria-label={title}>
      <div className={`glass mt-8 w-full ${wide ? 'max-w-4xl' : 'max-w-2xl'} bg-navy-surface/95 p-6`}>
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold">{title}</h2>
          <button onClick={onClose} className="text-2xl text-muted hover:text-white" aria-label={t.cancel}>×</button>
        </div>
        {children}
      </div>
    </div>
  )
}

let pushToast: ((msg: string, error?: boolean) => void) | null = null
export function toast(msg: string, error = false) {
  pushToast?.(msg, error)
}
export function Toaster() {
  const [items, setItems] = useState<{ id: number; msg: string; error: boolean }[]>([])
  useEffect(() => {
    pushToast = (msg, error = false) => {
      const id = Date.now() + Math.random()
      setItems((x) => [...x, { id, msg, error }])
      setTimeout(() => setItems((x) => x.filter((i) => i.id !== id)), 4000)
    }
    return () => {
      pushToast = null
    }
  }, [])
  return (
    <div className="fixed bottom-4 left-4 z-[60] flex flex-col gap-2">
      {items.map((i) => (
        <div key={i.id} className={`rounded-2xl px-4 py-3 text-sm shadow-lg ${i.error ? 'bg-danger text-white' : 'bg-navy-surface border border-white/15'}`}>
          {i.msg}
        </div>
      ))}
    </div>
  )
}

export function PageHeader({ title, actions }: { title: string; actions?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
      <h1 className="text-2xl font-extrabold">{title}</h1>
      <div className="flex flex-wrap gap-2">{actions}</div>
    </div>
  )
}

export function fmtDate(v?: string | null) {
  if (!v) return '—'
  const d = new Date(v)
  return isNaN(d.getTime()) ? v : d.toLocaleString('ar-IQ', { dateStyle: 'medium', timeStyle: 'short' })
}

/** <input type=datetime-local> <-> ISO helpers */
export function toLocalInput(iso?: string | null) {
  if (!iso) return ''
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}
export function fromLocalInput(v: string) {
  return v ? new Date(v).toISOString() : null
}
