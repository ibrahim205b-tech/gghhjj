import Papa from 'papaparse'

/** Flat import row (CSV columns / JSON keys). Ids refer to existing rows. */
export interface ImportRow {
  grade_id: string
  branch_id?: string
  year_id?: string
  subject_id: string
  chapter_id?: string
  topic_id?: string
  question_type: 'multiple_choice' | 'true_false' | 'short_answer'
  question_text: string
  options?: string[]          // multiple_choice / true_false
  correct_option?: number     // 1-based index into options
  answer_text?: string        // short_answer (alternatives separated by |)
  explanation?: string
  difficulty?: number
  source?: string
  source_type?: 'official_ministerial' | 'textbook' | 'practice' | 'teacher'
  question_year?: number
}

export interface ValidatedRow {
  line: number
  row?: ImportRow
  errors: string[]
}

export const CSV_TEMPLATE_HEADER = [
  'grade_id', 'branch_id', 'year_id', 'subject_id', 'chapter_id', 'topic_id', 'question_type', 'question_text',
  'option_1', 'option_2', 'option_3', 'option_4', 'correct_option', 'answer_text', 'explanation', 'difficulty',
  'source', 'source_type', 'question_year',
]

export const csvTemplate = () =>
  CSV_TEMPLATE_HEADER.join(',') + '\n' +
  ['<grade uuid>', '', '', '<subject uuid>', '', '', 'multiple_choice', '"ناتج 2+2 هو"', '3', '4', '5', '', '2', '',
    '"لأن 2+2=4"', '1', '', 'practice', ''].join(',') + '\n'

export const jsonTemplate = () =>
  JSON.stringify([
    {
      grade_id: '<grade uuid>', subject_id: '<subject uuid>', question_type: 'true_false',
      question_text: 'الماء يغلي عند 100 درجة مئوية عند مستوى سطح البحر', options: ['صح', 'خطأ'], correct_option: 1,
      explanation: '', difficulty: 1, source_type: 'practice',
    },
  ], null, 2)

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TYPES = ['multiple_choice', 'true_false', 'short_answer']
const SOURCE_TYPES = ['official_ministerial', 'textbook', 'practice', 'teacher']

export interface KnownIds {
  grades: Set<string>
  branches: Map<string, string> // branch -> grade
  subjects: Map<string, string> // subject -> grade
  chapters: Map<string, string> // chapter -> subject
}

function str(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined
  const s = String(v).trim()
  return s === '' ? undefined : s
}

/** Validates one raw object (from CSV or JSON). Returns normalised row + errors (Arabic). */
export function validateRow(raw: Record<string, unknown>, line: number, known?: KnownIds): ValidatedRow {
  const errors: string[] = []
  const options = Array.isArray(raw.options)
    ? (raw.options as unknown[]).map(str).filter((x): x is string => !!x)
    : [1, 2, 3, 4, 5, 6].map((i) => str(raw[`option_${i}`])).filter((x): x is string => !!x)
  const row: ImportRow = {
    grade_id: str(raw.grade_id) ?? '',
    branch_id: str(raw.branch_id),
    year_id: str(raw.year_id),
    subject_id: str(raw.subject_id) ?? '',
    chapter_id: str(raw.chapter_id),
    topic_id: str(raw.topic_id),
    question_type: (str(raw.question_type) ?? '') as ImportRow['question_type'],
    question_text: str(raw.question_text) ?? '',
    options,
    correct_option: raw.correct_option === undefined || raw.correct_option === '' ? undefined : Number(raw.correct_option),
    answer_text: str(raw.answer_text),
    explanation: str(raw.explanation),
    difficulty: raw.difficulty === undefined || raw.difficulty === '' ? 2 : Number(raw.difficulty),
    source: str(raw.source),
    source_type: (str(raw.source_type) ?? 'practice') as ImportRow['source_type'],
    question_year: raw.question_year === undefined || raw.question_year === '' ? undefined : Number(raw.question_year),
  }
  for (const k of ['grade_id', 'subject_id'] as const) {
    if (!UUID.test(row[k])) errors.push(`${k}: معرّف غير صالح`)
  }
  for (const k of ['branch_id', 'year_id', 'chapter_id', 'topic_id'] as const) {
    if (row[k] && !UUID.test(row[k]!)) errors.push(`${k}: معرّف غير صالح`)
  }
  if (!TYPES.includes(row.question_type)) errors.push('question_type: يجب أن يكون multiple_choice أو true_false أو short_answer')
  if (!row.question_text) errors.push('question_text: نص السؤال مطلوب')
  if (row.question_text.length > 5000) errors.push('question_text: أطول من 5000 حرف')
  if (row.question_type === 'short_answer') {
    if (!row.answer_text) errors.push('answer_text: مطلوب للجواب القصير')
  } else if (TYPES.includes(row.question_type)) {
    const min = row.question_type === 'true_false' ? 2 : 2
    if (options.length < min) errors.push('options: يحتاج خيارين على الأقل')
    if (row.question_type === 'true_false' && options.length !== 2) errors.push('options: صح/خطأ يحتاج خيارين بالضبط')
    if (!row.correct_option || !Number.isInteger(row.correct_option) || row.correct_option < 1 || row.correct_option > options.length) {
      errors.push('correct_option: رقم الخيار الصحيح غير صالح')
    }
  }
  if (!Number.isInteger(row.difficulty) || row.difficulty! < 1 || row.difficulty! > 3) errors.push('difficulty: من 1 إلى 3')
  if (!SOURCE_TYPES.includes(row.source_type!)) errors.push('source_type: قيمة غير صالحة')
  if (row.source_type === 'official_ministerial' && (!row.source || !row.question_year)) {
    errors.push('السؤال الوزاري يحتاج source و question_year حتى لا يُنسب سؤال للوزارة بدون دليل')
  }
  if (row.question_year !== undefined && (!Number.isInteger(row.question_year) || row.question_year < 1990 || row.question_year > 2100)) {
    errors.push('question_year: سنة غير صالحة')
  }
  if (known && errors.length === 0) {
    if (!known.grades.has(row.grade_id)) errors.push('grade_id: الصف غير موجود')
    if (known.subjects.get(row.subject_id) !== row.grade_id) errors.push('subject_id: المادة غير موجودة أو لا تتبع هذا الصف')
    if (row.branch_id && known.branches.get(row.branch_id) !== row.grade_id) errors.push('branch_id: الفرع لا يتبع هذا الصف')
    if (row.chapter_id && known.chapters.get(row.chapter_id) !== row.subject_id) errors.push('chapter_id: الفصل لا يتبع هذه المادة')
  }
  return { line, row: errors.length ? undefined : row, errors }
}

export function parseImport(text: string, fileName: string, known?: KnownIds): ValidatedRow[] {
  if (fileName.toLowerCase().endsWith('.json')) {
    let data: unknown
    try {
      data = JSON.parse(text)
    } catch {
      return [{ line: 0, errors: ['ملف JSON غير صالح'] }]
    }
    if (!Array.isArray(data)) return [{ line: 0, errors: ['يجب أن يكون الملف مصفوفة [ ... ]'] }]
    return data.map((r, i) => validateRow(r as Record<string, unknown>, i + 1, known))
  }
  const parsed = Papa.parse<Record<string, unknown>>(text.replace(/^﻿/, ''), { header: true, skipEmptyLines: true })
  if (parsed.errors.length && !parsed.data.length) return [{ line: 0, errors: ['ملف CSV غير صالح'] }]
  return parsed.data.map((r, i) => validateRow(r, i + 2, known))
}
