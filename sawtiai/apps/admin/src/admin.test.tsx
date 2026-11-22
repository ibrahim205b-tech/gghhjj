import { render, screen } from '@testing-library/react'
import { parseImport, validateRow, type KnownIds } from './lib/questionImport'
import { validateQuestion } from './pages/QuestionsPage'
import { validateAnnouncement, validateCampaign } from './pages/contentPages'
import App from './App'

const G = '11111111-1111-4111-8111-111111111111'
const S = '22222222-2222-4222-8222-222222222222'
const C = '33333333-3333-4333-8333-333333333333'
const known: KnownIds = {
  grades: new Set([G]),
  branches: new Map(),
  subjects: new Map([[S, G]]),
  chapters: new Map([[C, S]]),
}

describe('question import validation', () => {
  it('accepts a valid multiple-choice CSV row', () => {
    const csv = 'grade_id,subject_id,chapter_id,question_type,question_text,option_1,option_2,option_3,correct_option,difficulty,source_type\n' +
      `${G},${S},${C},multiple_choice,"ناتج 2+2 هو",3,4,5,2,1,practice\n`
    const r = parseImport(csv, 'q.csv', known)
    expect(r).toHaveLength(1)
    expect(r[0].errors).toEqual([])
    expect(r[0].row!.options).toEqual(['3', '4', '5'])
    expect(r[0].row!.correct_option).toBe(2)
  })

  it('rejects bad ids, missing text, wrong correct option and unknown subject', () => {
    const v = validateRow({ grade_id: 'x', subject_id: S, question_type: 'multiple_choice', question_text: '', options: ['a', 'b'], correct_option: 5 }, 2)
    expect(v.row).toBeUndefined()
    expect(v.errors.join(' ')).toMatch(/grade_id/)
    expect(v.errors.join(' ')).toMatch(/question_text/)
    expect(v.errors.join(' ')).toMatch(/correct_option/)
    const other = validateRow({ grade_id: G, subject_id: '44444444-4444-4444-8444-444444444444', question_type: 'true_false',
      question_text: 'x', options: ['صح', 'خطأ'], correct_option: 1 }, 3, known)
    expect(other.errors.join(' ')).toMatch(/subject_id/)
  })

  it('refuses to mark a question as ministerial without source and year', () => {
    const v = validateRow({ grade_id: G, subject_id: S, question_type: 'short_answer', question_text: 'س', answer_text: 'ج', source_type: 'official_ministerial' }, 1)
    expect(v.errors.join(' ')).toMatch(/الوزاري/)
  })

  it('parses JSON arrays and reports malformed JSON', () => {
    const ok = parseImport(JSON.stringify([{ grade_id: G, subject_id: S, question_type: 'short_answer', question_text: 'عاصمة العراق؟', answer_text: 'بغداد' }]), 'q.json', known)
    expect(ok[0].errors).toEqual([])
    expect(parseImport('{bad', 'q.json')[0].errors[0]).toMatch(/JSON/)
    expect(parseImport('{}', 'q.json')[0].errors[0]).toMatch(/مصفوفة/)
  })
})

describe('form validators', () => {
  it('question editor rules', () => {
    const base = { grade_id: G, subject_id: S, question_text: 'س', source_type: 'practice', status: 'draft' }
    expect(validateQuestion({ ...base, question_type: 'multiple_choice', options: [{ option_text: 'a', is_correct: true }, { option_text: 'b', is_correct: false }] })).toBeNull()
    expect(validateQuestion({ ...base, question_type: 'multiple_choice', options: [{ option_text: 'a', is_correct: true }, { option_text: 'b', is_correct: true }] })).toMatch(/صحيحاً واحداً/)
    expect(validateQuestion({ ...base, question_type: 'short_answer', options: [] })).toMatch(/الجواب/)
    expect(validateQuestion({ ...base, question_type: 'true_false', status: 'scheduled', options: [{ option_text: 'صح', is_correct: true }, { option_text: 'خطأ', is_correct: false }] })).toMatch(/موعد/)
  })

  it('announcement rules', () => {
    expect(validateAnnouncement({ title: 'تحديث', target_all: true, status: 'published' })).toBeNull()
    expect(validateAnnouncement({ title: 'x', target_all: true, telegram_url: 'https://evil.example/x' })).toMatch(/التليجرام/)
    expect(validateAnnouncement({ title: 'x', target_all: false })).toMatch(/جمهور/)
    expect(validateAnnouncement({ title: 'x', target_all: true, action_url: 'javascript:alert(1)' })).toMatch(/رابط الزر/)
  })

  it('notification rules', () => {
    expect(validateCampaign({ title: 'هلا بيك!', body: 'نزلنا إلك أسئلة جديدة', audience: 'all' })).toBeNull()
    expect(validateCampaign({ title: 'x', body: 'y', audience: 'grade', target_grade_ids: [] })).toMatch(/صفاً/)
    expect(validateCampaign({ title: 'x', body: 'y', audience: 'all', deep_link: 'https://x' })).toMatch(/enjaz/)
  })
})

describe('app shell', () => {
  it('without backend config the login page says so (no fake login)', async () => {
    render(<App />)
    expect(await screen.findByText(/لم يتم ربط لوحة الإدارة/)).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'دخول' })).toBeNull()
  })
})
