import { HashRouter, NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { useState } from 'react'
import { AuthProvider, useAuth } from './lib/auth'
import { t } from './lib/strings'
import { Button, Toaster } from './components/ui'
import { ActivityPage, AdminsPage, LoginPage, OverviewPage, StudentsPage } from './pages/corePages'
import { AcademicPage, AppVersionsPage, GuidancePage, MotivationPage, OfficialExamsPage, SettingsPage } from './pages/configPages'
import { QuestionsPage } from './pages/QuestionsPage'
import { AnnouncementsPage, LibraryPage, NotificationsPage } from './pages/contentPages'

const NAV: { to: string; label: string; icon: string }[] = [
  { to: '/', label: t.overview, icon: '📊' },
  { to: '/students', label: t.students, icon: '👥' },
  { to: '/academic', label: t.academic, icon: '🏫' },
  { to: '/questions', label: t.questions, icon: '❓' },
  { to: '/library', label: t.library, icon: '📚' },
  { to: '/motivation', label: t.motivation, icon: '✨' },
  { to: '/announcements', label: t.announcements, icon: '📢' },
  { to: '/notifications', label: t.notifications, icon: '🔔' },
  { to: '/versions', label: t.appVersions, icon: '⬆️' },
  { to: '/exams', label: t.officialExams, icon: '🗓️' },
  { to: '/guidance', label: t.guidance, icon: '🎓' },
  { to: '/settings', label: t.settings, icon: '⚙️' },
  { to: '/activity', label: t.activity, icon: '🧾' },
  { to: '/admins', label: t.admins, icon: '🛡️' },
]

function Shell() {
  const { session, role, signOut } = useAuth()
  const [menu, setMenu] = useState(false)
  return (
    <div className="flex min-h-screen">
      <aside className={`fixed inset-y-0 right-0 z-40 w-64 transform border-l border-white/10 bg-navy-deep/90 p-4 backdrop-blur transition md:static md:translate-x-0 ${menu ? 'translate-x-0' : 'translate-x-full'}`}>
        <div className="mb-6 flex items-center gap-3">
          <img src="./favicon.svg" alt="" className="h-10 w-10" />
          <div><p className="text-xl font-black">{t.appName}</p><p className="text-xs text-muted">{t.dashboard}</p></div>
        </div>
        <nav className="space-y-1">
          {NAV.filter((n) => n.to !== '/admins' || role === 'super_admin').map((n) => (
            <NavLink key={n.to} to={n.to} end={n.to === '/'} onClick={() => setMenu(false)}
              className={({ isActive }) => `flex items-center gap-3 rounded-2xl px-3 py-2 text-sm ${isActive ? 'btn-brand text-white' : 'hover:bg-white/5'}`}>
              <span aria-hidden>{n.icon}</span>{n.label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-6 border-t border-white/10 pt-4 text-xs text-muted">
          <p dir="ltr" className="truncate text-start">{session?.user.email}</p>
          <p>{role}</p>
          <Button variant="ghost" className="mt-2 w-full" onClick={signOut}>{t.signOut}</Button>
        </div>
      </aside>
      <main className="min-w-0 flex-1 p-4 md:p-8">
        <button className="mb-4 rounded-full border border-white/15 px-3 py-1 md:hidden" onClick={() => setMenu(!menu)} aria-label="menu">☰</button>
        <Routes>
          <Route path="/" element={<OverviewPage />} />
          <Route path="/students" element={<StudentsPage />} />
          <Route path="/academic" element={<AcademicPage />} />
          <Route path="/questions" element={<QuestionsPage />} />
          <Route path="/library" element={<LibraryPage />} />
          <Route path="/motivation" element={<MotivationPage />} />
          <Route path="/announcements" element={<AnnouncementsPage />} />
          <Route path="/notifications" element={<NotificationsPage />} />
          <Route path="/versions" element={<AppVersionsPage />} />
          <Route path="/exams" element={<OfficialExamsPage />} />
          <Route path="/guidance" element={<GuidancePage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/activity" element={<ActivityPage />} />
          <Route path="/admins" element={<AdminsPage />} />
          <Route path="*" element={<Navigate to="/" />} />
        </Routes>
      </main>
    </div>
  )
}

function Gate() {
  const { session, role, loading } = useAuth()
  if (loading) return <p className="p-8 text-muted">{t.loading}</p>
  if (!session || !role) return <LoginPage />
  return <Shell />
}

export default function App() {
  return (
    <AuthProvider>
      <HashRouter>
        <Gate />
      </HashRouter>
      <Toaster />
    </AuthProvider>
  )
}
