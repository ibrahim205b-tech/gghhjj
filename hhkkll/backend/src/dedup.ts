// Port of hhkkll/core/lib/src/normalize.dart + dedup.dart. Both sides are
// checked against core/test/fixtures/normalize_vectors.json so the app and
// the server agree on what counts as "the same question".
import { createHash } from "node:crypto";
import type { Question } from "./types.js";

const ARABIC_DIACRITICS = /[ؐ-ًؚ-ٰٟۖ-ۭـ]/g;

const CHAR_MAP: Record<string, string> = {
  "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
  "ى": "ي", "ئ": "ي", "ؤ": "و", "ة": "ه",
  "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
  "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
  "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a",
  "ç": "c", "č": "c", "ć": "c",
  "è": "e", "é": "e", "ê": "e", "ë": "e",
  "ì": "i", "í": "i", "î": "i", "ï": "i",
  "ñ": "n", "ń": "n",
  "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o",
  "ù": "u", "ú": "u", "û": "u", "ü": "u",
  "ý": "y", "ÿ": "y", "š": "s", "ş": "s", "ș": "s", "ž": "z", "ğ": "g",
  "ł": "l", "ß": "ss", "æ": "ae", "œ": "oe", "đ": "d", "ı": "i",
  "ř": "r", "ț": "t", "ţ": "t",
};

export const STOPWORDS = new Set([
  "من", "في", "على", "الي", "عن", "ما", "ماذا", "هو", "هي", "كم", "اي",
  "الذي", "التي", "الذين", "مع", "او", "و", "هل", "كان", "كانت", "تم", "قد",
  "لقد", "ثم", "بعد", "قبل", "حتي", "منذ", "هذا", "هذه", "ذلك", "تلك", "لم",
  "لا", "ان", "انه", "به", "بها", "له", "لها", "عام", "سنه", "موسم",
  "اذكر", "سم", "سمي", "تستطيع", "تسميه", "تسميتهم", "لاعبا", "لاعب", "لاعبين",
  "اول", "اخر", "مره", "نسخه", "بطوله",
  "the", "a", "an", "of", "in", "on", "at", "to", "for", "by", "with", "and",
  "or", "is", "was", "were", "which", "who", "what", "how", "many", "did",
  "does", "from", "that", "this", "name", "player", "players", "season",
  "first", "last", "year",
]);

export function normalizeText(input: string): string {
  let s = input.toLowerCase().replace(ARABIC_DIACRITICS, "");
  let b = "";
  for (const ch of s) b += CHAR_MAP[ch] ?? ch;
  s = b.replace(/[^\p{L}\p{N}]+/gu, " ");
  return s.trim().replace(/\s+/g, " ");
}

export function stemToken(t: string): string {
  let s = t;
  if (s.length > 4 && (s.startsWith("وال") || s.startsWith("بال") || s.startsWith("فال") || s.startsWith("كال"))) {
    s = s.substring(3);
  } else if (s.length > 3 && s.startsWith("لل")) {
    s = s[2] === "ا" ? s.substring(1) : s.substring(2);
  } else if (s.length > 3 && s.startsWith("ال")) {
    s = s.substring(2);
  } else if (s.length > 4 && s.startsWith("و") && !s.startsWith("وو")) {
    s = s.substring(1);
  }
  return s;
}

export function contentTokens(input: string): string[] {
  const out: string[] = [];
  for (const raw of normalizeText(input).split(" ")) {
    if (!raw || STOPWORDS.has(raw)) continue;
    const t = stemToken(raw);
    if (!t || STOPWORDS.has(t)) continue;
    out.push(t);
  }
  return out;
}

export function normalizeAnswer(input: string): string {
  const t = contentTokens(input);
  return t.length === 0 ? normalizeText(input).replace(/ /g, "") : t.join("");
}

export function trigrams(input: string): Set<string> {
  const joined = ` ${contentTokens(input).join(" ")} `;
  const out = new Set<string>();
  for (let i = 0; i + 3 <= joined.length; i++) out.add(joined.substring(i, i + 3));
  return out;
}

export function numberTokens(input: string): Set<string> {
  return new Set(normalizeText(input).match(/\d+/g) ?? []);
}

export function jaccard<T>(a: Set<T>, b: Set<T>): number {
  if (a.size === 0 && b.size === 0) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}

export function textSimilarity(a: string, b: string): number {
  return jaccard(trigrams(a), trigrams(b));
}

const sha1 = (s: string) => createHash("sha1").update(s, "utf8").digest("hex").substring(0, 20);

const sortCodeUnits = (xs: string[]) => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

/** Same rule as Question.fingerprintText in Dart. */
export function fingerprintText(q: Pick<Question, "category" | "question" | "clues">): string {
  return q.category === "whoami" && q.clues && q.clues.length > 0 ? q.clues.join(" ") : q.question;
}

export function textFingerprint(q: Pick<Question, "category" | "question" | "clues">): string {
  return sha1(`txt:${sortCodeUnits([...new Set(contentTokens(fingerprintText(q)))]).join(" ")}`);
}

export function answerKeys(q: Pick<Question, "answer" | "accepted_answers"> & { category?: string }): Set<string> {
  if (q.category === "auction") return new Set();
  return new Set([q.answer, ...(q.accepted_answers ?? [])].map(normalizeAnswer).filter((s) => s.length > 0));
}

export function semanticFingerprint(q: Question): string {
  if (q.semantic_key.trim()) {
    return sha1(`sem:${normalizeText(q.semantic_key).replace(/ /g, "-")}`);
  }
  const ans = sortCodeUnits([...answerKeys(q)]);
  const toks = sortCodeUnits([...new Set(contentTokens(fingerprintText(q)))]).slice(0, 6);
  return sha1(`ans:[${ans.join(", ")}]|${toks.join(",")}`);
}

export interface DedupEntry {
  id: string;
  category: string;
  textFp: string;
  semanticFp: string;
  answerKeys: Set<string>;
  itemKeys: Set<string>;
  trigrams: Set<string>;
  numbers: Set<string>;
  semanticKey: string;
  factKey: string;
  answer: string;
}

export function entryOf(q: Question): DedupEntry {
  const ft = fingerprintText(q);
  return {
    id: q.id,
    category: q.category,
    textFp: textFingerprint(q),
    semanticFp: semanticFingerprint(q),
    answerKeys: answerKeys(q),
    itemKeys: new Set((q.items ?? []).map((i) => normalizeAnswer(i.name))),
    trigrams: trigrams(ft),
    numbers: numberTokens(ft),
    semanticKey: q.semantic_key,
    factKey: normalizeText(q.semantic_key ?? ""),
    answer: q.answer,
  };
}

export interface DuplicateReason {
  code: string;
  otherId: string;
  score?: number;
}

export const THRESHOLDS = {
  nearIdenticalText: 0.72,
  sameAnswerText: 0.3,
  auctionItemOverlap: 0.6,
  sameAnswerDifferentKeyText: 0.55,
  nearIdenticalDifferentAnswer: 0.9,
};

export class DedupIndex {
  private byId = new Map<string, DedupEntry>();
  private byText = new Map<string, string>();
  private bySem = new Map<string, string>();

  get size(): number {
    return this.byId.size;
  }
  entries(): IterableIterator<DedupEntry> {
    return this.byId.values();
  }
  bySemanticFp(fp: string): DedupEntry | undefined {
    const id = this.bySem.get(fp);
    return id ? this.byId.get(id) : undefined;
  }

  check(q: Question): DuplicateReason | null {
    return this.checkEntry(entryOf(q));
  }

  checkEntry(c: DedupEntry): DuplicateReason | null {
    if (this.byId.has(c.id)) return { code: "same-id", otherId: c.id };
    const t = this.byText.get(c.textFp);
    if (t) return { code: "same-wording", otherId: t };
    const s = this.bySem.get(c.semanticFp);
    if (s) return { code: "same-fact", otherId: s };
    for (const e of this.byId.values()) {
      const sim = jaccard(c.trigrams, e.trigrams);
      const sameNumbers = c.numbers.size === e.numbers.size && [...c.numbers].every((n) => e.numbers.has(n));
      let sameAnswer = false;
      for (const a of c.answerKeys) if (e.answerKeys.has(a)) sameAnswer = true;
      if (
        sameNumbers &&
        (sim >= THRESHOLDS.nearIdenticalDifferentAnswer || (sim >= THRESHOLDS.nearIdenticalText && sameAnswer))
      ) {
        return { code: "near-identical-wording", otherId: e.id, score: sim };
      }
      const differentKeys = c.factKey !== "" && e.factKey !== "" && c.factKey !== e.factKey;
      if (sameAnswer) {
        if (c.category === "whoami" && e.category === "whoami") return { code: "same-riddle-subject", otherId: e.id };
        const need = differentKeys ? THRESHOLDS.sameAnswerDifferentKeyText : THRESHOLDS.sameAnswerText;
        if (sim >= need && sameNumbers) return { code: "same-answer-similar-question", otherId: e.id, score: sim };
      }
      if (c.itemKeys.size >= 3 && e.itemKeys.size >= 3) {
        const overlap = jaccard(c.itemKeys, e.itemKeys);
        if (overlap >= THRESHOLDS.auctionItemOverlap) return { code: "same-answer-set", otherId: e.id, score: overlap };
      }
    }
    return null;
  }

  add(e: DedupEntry): void {
    this.byId.set(e.id, e);
    this.byText.set(e.textFp, e.id);
    this.bySem.set(e.semanticFp, e.id);
  }

  addQuestion(q: Question): void {
    this.add(entryOf(q));
  }

  tryAdd(q: Question): DuplicateReason | null {
    const e = entryOf(q);
    const r = this.checkEntry(e);
    if (!r) this.add(e);
    return r;
  }
}
