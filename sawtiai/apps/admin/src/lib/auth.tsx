import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'

export type AdminRole = 'super_admin' | 'admin' | 'editor'

interface AuthState {
  session: Session | null
  role: AdminRole | null
  loading: boolean
  denied: boolean
  signIn: (email: string, password: string) => Promise<string | null>
  signOut: () => Promise<void>
}

const Ctx = createContext<AuthState | null>(null)

/** Reads the caller's own admin_roles row (RLS lets a user read only their own). */
async function fetchRole(userId: string): Promise<AdminRole | null> {
  if (!supabase) return null
  const { data } = await supabase.from('admin_roles').select('role').eq('user_id', userId).maybeSingle()
  return (data?.role as AdminRole) ?? null
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [role, setRole] = useState<AdminRole | null>(null)
  const [loading, setLoading] = useState(true)
  const [denied, setDenied] = useState(false)

  useEffect(() => {
    if (!supabase) {
      setLoading(false)
      return
    }
    const apply = async (s: Session | null) => {
      setSession(s)
      if (!s) {
        setRole(null)
        setLoading(false)
        return
      }
      const r = await fetchRole(s.user.id)
      if (!r) {
        // Signed in but not an administrator: never keep the session here.
        setDenied(true)
        await supabase!.auth.signOut()
        setSession(null)
      }
      setRole(r)
      setLoading(false)
    }
    supabase.auth.getSession().then(({ data }) => apply(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      void apply(s)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const value: AuthState = {
    session,
    role,
    loading,
    denied,
    async signIn(email, password) {
      if (!supabase) return 'backend'
      setDenied(false)
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      return error ? error.message : null
    },
    async signOut() {
      await supabase?.auth.signOut()
    },
  }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth(): AuthState {
  const v = useContext(Ctx)
  if (!v) throw new Error('AuthProvider missing')
  return v
}
