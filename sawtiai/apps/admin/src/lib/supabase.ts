import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

/** Public client (anon/publishable key). Every privileged action is enforced
 *  by RLS and security-definer functions in the database, never in the UI. */
export const supabase: SupabaseClient | null =
  url && url.startsWith('https://') && key ? createClient(url, key, { auth: { persistSession: true } }) : null

export const backendConfigured = supabase !== null

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Row = Record<string, any>

export function db(): SupabaseClient {
  if (!supabase) throw new Error('backend_not_configured')
  return supabase
}

/** Uploads to a storage bucket under a random name and returns the path. */
export async function uploadFile(bucket: 'content' | 'library', file: File, folder: string): Promise<string> {
  const ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '')
  const path = `${folder}/${crypto.randomUUID()}.${ext}`
  const { error } = await db().storage.from(bucket).upload(path, file, { contentType: file.type, upsert: false })
  if (error) throw error
  return path
}

export function publicUrl(path?: string | null): string | null {
  if (!path || !supabase) return null
  if (path.startsWith('https://')) return path
  return supabase.storage.from('content').getPublicUrl(path).data.publicUrl
}
