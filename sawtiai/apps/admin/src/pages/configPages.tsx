import { useState } from 'react'
import { CrudPage, type CrudConfig } from '../components/CrudPage'
import { publicUrl, type Row } from '../lib/supabase'
import { t } from '../lib/strings'

const difficulty = [{ value: '1', label: 'سهل' }, { value: '2', label: 'متوسط' }, { value: '3', label: 'صعب' }]
const httpsOk = (v?: string | null) => !v || v.startsWith('https://')

// ---------------------------------------------------------------------------
// Academic structure
// ---------------------------------------------------------------------------
const academicConfigs: Record<string, CrudConfig> = {
  stages: {
    table: 'academic_stages', title: 'المراحل', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'name_ar', label: 'الاسم بالعربي', type: 'text', required: true, inTable: true },
      { key: 'name_en', label: 'الاسم بالإنكليزي', type: 'text', required: true, inTable: true },
      { key: 'code', label: 'الرمز (code)', type: 'text', required: true, inTable: true },
    ],
  },
  grades: {
    table: 'grades', title: 'الصفوف', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'stage_id', label: t.stage, type: 'ref', ref: { table: 'academic_stages', label: 'name_ar' }, required: true, inTable: true },
      { key: 'name_ar', label: 'الاسم بالعربي', type: 'text', required: true, inTable: true },
      { key: 'name_en', label: 'الاسم بالإنكليزي', type: 'text', required: true },
      { key: 'code', label: 'الرمز (code)', type: 'text', required: true, inTable: true },
      { key: 'has_branches', label: 'لديه فروع', type: 'bool', inTable: true, default: false },
    ],
  },
  branches: {
    table: 'academic_branches', title: 'الفروع', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'grade_id', label: t.grade, type: 'ref', ref: { table: 'grades', label: 'name_ar' }, required: true, inTable: true },
      { key: 'name_ar', label: 'الاسم بالعربي', type: 'text', required: true, inTable: true },
      { key: 'name_en', label: 'الاسم بالإنكليزي', type: 'text', required: true },
      { key: 'code', label: 'الرمز (code)', type: 'text', required: true, inTable: true },
    ],
  },
  years: {
    table: 'academic_years', title: 'السنوات الدراسية', activatable: true, softDelete: true,
    orderBy: { column: 'label', ascending: false },
    fields: [
      { key: 'label', label: 'السنة', type: 'text', required: true, inTable: true, hint: 'مثال: 2026-2027' },
      { key: 'starts_on', label: 'تبدأ', type: 'date', inTable: true },
      { key: 'ends_on', label: 'تنتهي', type: 'date' },
      { key: 'is_current', label: 'السنة الحالية', type: 'bool', inTable: true, default: false },
    ],
  },
  subjects: {
    table: 'subjects', title: 'المواد', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'grade_id', label: t.grade, type: 'ref', ref: { table: 'grades', label: 'name_ar' }, required: true, inTable: true },
      { key: 'branch_id', label: `${t.branch} (فارغ = كل الفروع)`, type: 'ref', ref: { table: 'academic_branches', label: 'name_ar', filter: { grade_id: '$grade_id' } }, inTable: true },
      { key: 'year_id', label: `${t.year} (فارغ = كل السنوات)`, type: 'ref', ref: { table: 'academic_years', label: 'label' } },
      { key: 'name_ar', label: 'اسم المادة', type: 'text', required: true, inTable: true },
      { key: 'icon', label: 'الأيقونة', type: 'select', default: 'book', options: ['book', 'math', 'science', 'physics', 'chemistry', 'biology', 'arabic', 'english', 'islamic', 'history', 'geography', 'computer', 'economy', 'art', 'language'].map((v) => ({ value: v, label: v })) },
      { key: 'color', label: 'اللون', type: 'color', default: '#4F8CFF', inTable: true },
      { key: 'is_verified', label: 'مطابقة للمنهج الرسمي (تم التحقق)', type: 'bool', inTable: true, default: false },
      { key: 'source_note', label: 'مصدر التحقق', type: 'text' },
    ],
  },
  chapters: {
    table: 'chapters', title: 'الفصول', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'subject_id', label: t.subject, type: 'ref', ref: { table: 'subjects', label: 'name_ar' }, required: true, inTable: true },
      { key: 'title', label: t.title, type: 'text', required: true, inTable: true },
    ],
  },
  topics: {
    table: 'topics', title: 'المواضيع', sortable: true, activatable: true, softDelete: true,
    fields: [
      { key: 'chapter_id', label: t.chapter, type: 'ref', ref: { table: 'chapters', label: 'title' }, required: true, inTable: true },
      { key: 'title', label: t.title, type: 'text', required: true, inTable: true },
      { key: 'difficulty', label: t.difficulty, type: 'select', options: difficulty, default: '2', inTable: true },
    ],
  },
}

export function Tabs({ tabs, children }: { tabs: { id: string; label: string }[]; children: (id: string) => React.ReactNode }) {
  const [cur, setCur] = useState(tabs[0].id)
  return (
    <div>
      <div className="mb-5 flex flex-wrap gap-2">
        {tabs.map((tb) => (
          <button key={tb.id} onClick={() => setCur(tb.id)}
            className={`rounded-full px-4 py-1.5 text-sm ${cur === tb.id ? 'btn-brand text-white' : 'bg-white/5 border border-white/10'}`}>
            {tb.label}
          </button>
        ))}
      </div>
      {children(cur)}
    </div>
  )
}

export function AcademicPage() {
  const tabs = Object.entries(academicConfigs).map(([id, c]) => ({ id, label: c.title }))
  return <Tabs tabs={tabs}>{(id) => <CrudPage key={id} config={academicConfigs[id]} />}</Tabs>
}

// ---------------------------------------------------------------------------
// Official exam dates
// ---------------------------------------------------------------------------
export function OfficialExamsPage() {
  return (
    <CrudPage config={{
      table: 'exams', title: t.officialExams, publishable: true, softDelete: true,
      baseFilter: { is_official: true }, defaults: { user_id: null },
      orderBy: { column: 'exam_at', ascending: true },
      fields: [
        { key: 'title', label: t.title, type: 'text', required: true, inTable: true },
        { key: 'grade_id', label: t.grade, type: 'ref', ref: { table: 'grades', label: 'name_ar' }, inTable: true },
        { key: 'branch_id', label: t.branch, type: 'ref', ref: { table: 'academic_branches', label: 'name_ar', filter: { grade_id: '$grade_id' } } },
        { key: 'subject_id', label: t.subject, type: 'ref', ref: { table: 'subjects', label: 'name_ar', filter: { grade_id: '$grade_id' } }, inTable: true },
        { key: 'exam_at', label: 'موعد الامتحان', type: 'datetime', required: true, inTable: true },
        { key: 'location', label: 'المكان', type: 'text' },
        { key: 'source_url', label: t.sourceUrl, type: 'url', required: true, hint: 'رابط الإعلان الرسمي (وزارة التربية) — إلزامي' },
        { key: 'verified_at', label: t.verifiedAt, type: 'datetime', required: true },
      ],
      validate: (v) => (httpsOk(v.source_url) ? null : 'رابط المصدر يجب أن يبدأ بـ https://'),
    }} />
  )
}

// ---------------------------------------------------------------------------
// Daily motivation
// ---------------------------------------------------------------------------
function MotivationPreview({ v }: { v: Row }) {
  const img = publicUrl(v.image_path)
  return (
    <div className="max-w-sm overflow-hidden rounded-3xl" style={{ background: 'linear-gradient(135deg, rgba(108,99,255,.6), rgba(79,140,255,.45))' }}>
      {img && <img src={img} alt="" className="h-40 w-full object-cover" />}
      <div className="p-5">
        {v.title && <p className="font-bold">{v.title}</p>}
        <p className="mt-1 text-lg leading-8">{v.body || '…'}</p>
        {v.author && v.author_verified && <p className="mt-2 text-white/70">— {v.author}</p>}
      </div>
    </div>
  )
}

export function MotivationPage() {
  return (
    <CrudPage config={{
      table: 'daily_motivations', title: t.motivation, publishable: true, softDelete: true,
      fields: [
        { key: 'title', label: t.title, type: 'text', inTable: true },
        { key: 'body', label: t.body, type: 'textarea', required: true, inTable: true },
        { key: 'image_path', label: t.image, type: 'image', inTable: true },
        { key: 'author', label: t.author, type: 'text' },
        { key: 'author_verified', label: t.authorVerified, type: 'bool', default: false },
        { key: 'show_on', label: t.showOn, type: 'date', inTable: true },
        { key: 'target_stage_ids', label: t.targetStages, type: 'refMulti', ref: { table: 'academic_stages', label: 'name_ar' }, default: [] },
        { key: 'target_grade_ids', label: t.targetGrades, type: 'refMulti', ref: { table: 'grades', label: 'name_ar' }, default: [], inTable: true },
        { key: 'target_branch_ids', label: t.targetBranches, type: 'refMulti', ref: { table: 'academic_branches', label: 'name_ar' }, default: [] },
      ],
      preview: (v) => <MotivationPreview v={v} />,
    }} />
  )
}

// ---------------------------------------------------------------------------
// App versions / update announcements
// ---------------------------------------------------------------------------
export function AppVersionsPage() {
  return (
    <CrudPage config={{
      table: 'app_versions', title: t.appVersions, publishable: true,
      orderBy: { column: 'build_number', ascending: false },
      fields: [
        { key: 'version_name', label: t.versionName, type: 'text', required: true, inTable: true, hint: 'مثال: 1.2.0' },
        { key: 'build_number', label: t.buildNumber, type: 'number', required: true, inTable: true, hint: 'نفس الرقم بعد + في pubspec.yaml' },
        { key: 'release_date', label: t.releaseDate, type: 'date', inTable: true },
        { key: 'description', label: t.description, type: 'textarea' },
        { key: 'image_path', label: t.image, type: 'image' },
        { key: 'download_url', label: t.downloadUrl, type: 'url' },
        { key: 'play_store_url', label: t.playStoreUrl, type: 'url' },
        { key: 'telegram_url', label: t.telegramUrl, type: 'url' },
        { key: 'min_supported_build', label: t.minSupportedBuild, type: 'number', default: 1, inTable: true },
        { key: 'is_mandatory', label: t.mandatory, type: 'bool', default: false, inTable: true },
      ],
      validate: (v) => {
        if (!v.download_url && !v.play_store_url && !v.telegram_url) return 'أضف رابط تنزيل أو Google Play أو تليجرام'
        if (![v.download_url, v.play_store_url, v.telegram_url].every(httpsOk)) return 'كل الروابط يجب أن تبدأ بـ https://'
        if (v.telegram_url && !/^https:\/\/(t\.me|telegram\.me)\//.test(v.telegram_url)) return 'رابط التليجرام يجب أن يبدأ بـ https://t.me/'
        return null
      },
    }} />
  )
}

// ---------------------------------------------------------------------------
// App settings (key/value)
// ---------------------------------------------------------------------------
export function SettingsPage() {
  return (
    <CrudPage config={{
      table: 'app_settings', title: t.settings, primaryKey: 'key', orderBy: { column: 'key', ascending: true },
      fields: [
        { key: 'key', label: 'المفتاح', type: 'text', required: true, inTable: true, hint: 'telegram_channel_url, support_contact, governorates ...' },
        { key: 'value', label: 'القيمة (JSON)', type: 'json', required: true, inTable: true, hint: 'نص بين علامتي تنصيص: "https://t.me/..."' },
        { key: 'is_public', label: 'يظهر للطلاب', type: 'bool', default: true, inTable: true },
      ],
    }} />
  )
}

// ---------------------------------------------------------------------------
// Universities & admission guidance
// ---------------------------------------------------------------------------
const guidanceConfigs: Record<string, CrudConfig> = {
  universities: {
    table: 'universities', title: t.universities, publishable: true, softDelete: true, orderBy: { column: 'name_ar' },
    fields: [
      { key: 'name_ar', label: 'الاسم', type: 'text', required: true, inTable: true },
      { key: 'governorate', label: 'المحافظة', type: 'text', inTable: true },
      { key: 'kind', label: t.type, type: 'select', required: true, default: 'public', inTable: true,
        options: [{ value: 'public', label: 'حكومية' }, { value: 'private', label: 'أهلية' }, { value: 'institute', label: 'معهد' }] },
      { key: 'website', label: 'الموقع', type: 'url' },
      { key: 'description', label: t.description, type: 'textarea' },
    ],
  },
  colleges: {
    table: 'colleges', title: t.colleges, softDelete: true, sortable: true,
    fields: [
      { key: 'university_id', label: 'الجامعة', type: 'ref', ref: { table: 'universities', label: 'name_ar' }, required: true, inTable: true },
      { key: 'name_ar', label: 'الاسم', type: 'text', required: true, inTable: true },
      { key: 'description', label: t.description, type: 'textarea' },
    ],
  },
  specializations: {
    table: 'specializations', title: t.specializations, softDelete: true,
    fields: [
      { key: 'college_id', label: 'الكلية', type: 'ref', ref: { table: 'colleges', label: 'name_ar' }, required: true, inTable: true },
      { key: 'name_ar', label: 'الاسم', type: 'text', required: true, inTable: true },
      { key: 'study_years', label: 'سنوات الدراسة', type: 'number', inTable: true },
      { key: 'description', label: t.description, type: 'textarea' },
    ],
  },
  admission: {
    table: 'admission_information', title: t.admission, publishable: true, softDelete: true,
    fields: [
      { key: 'college_id', label: 'الكلية', type: 'ref', ref: { table: 'colleges', label: 'name_ar' }, inTable: true },
      { key: 'specialization_id', label: 'التخصص', type: 'ref', ref: { table: 'specializations', label: 'name_ar' }, inTable: true },
      { key: 'academic_year_label', label: t.year, type: 'text', required: true, inTable: true },
      { key: 'admission_channel', label: 'قناة القبول', type: 'select', required: true, default: 'central',
        options: [{ value: 'central', label: 'مركزي' }, { value: 'parallel', label: 'موازي' }, { value: 'evening', label: 'مسائي' },
          { value: 'private', label: 'أهلي' }, { value: 'scholarship', label: 'منحة' }, { value: 'other', label: 'أخرى' }] },
      { key: 'min_average', label: t.minAverage, type: 'number', inTable: true },
      { key: 'application_deadline', label: t.deadline, type: 'date' },
      { key: 'details', label: t.description, type: 'textarea' },
      { key: 'source_name', label: t.sourceName, type: 'text', required: true, inTable: true },
      { key: 'source_url', label: t.sourceUrl, type: 'url' },
      { key: 'is_official', label: t.isOfficial, type: 'bool', default: false, inTable: true },
      { key: 'verified_at', label: t.verifiedAt, type: 'datetime', showIf: (v) => !!v.is_official },
    ],
    validate: (v) => {
      if (!v.college_id && !v.specialization_id) return 'اختر كلية أو تخصص'
      if (v.is_official && !v.verified_at) return 'المعلومة الرسمية تحتاج تاريخ تحقق — لا تُعلَّم رسمية بدون تحقق'
      if (v.min_average !== null && v.min_average !== undefined && (v.min_average < 0 || v.min_average > 100)) return 'المعدل بين 0 و 100'
      return null
    },
  },
}

export function GuidancePage() {
  const tabs = Object.entries(guidanceConfigs).map(([id, c]) => ({ id, label: c.title }))
  return <Tabs tabs={tabs}>{(id) => <CrudPage key={id} config={guidanceConfigs[id]} />}</Tabs>
}
