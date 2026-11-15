import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { DedupIndex, semanticFingerprint, textFingerprint } from "./dedup.js";
import type { Category, Question } from "./types.js";

/**
 * The pool of accepted (verified) questions. Kept as one JSON file so it can
 * live on a small server disk or be committed to the feed branch.
 */
export class QuestionStore {
  private readonly questions = new Map<string, Question>();
  readonly index = new DedupIndex();

  constructor(private readonly file?: string) {
    if (file && existsSync(file)) {
      const j = JSON.parse(readFileSync(file, "utf8")) as { questions: Question[] };
      for (const q of j.questions) this.insert(q);
    }
  }

  get size(): number {
    return this.questions.size;
  }

  all(): Question[] {
    return [...this.questions.values()];
  }

  byCategory(c: Category): Question[] {
    return this.all().filter((q) => q.category === c);
  }

  /** Adds without checking (used when loading). */
  private insert(q: Question): void {
    const withFp = { ...q, text_fp: textFingerprint(q), semantic_fp: semanticFingerprint(q) };
    this.questions.set(q.id, withFp);
    this.index.addQuestion(withFp);
  }

  /** Adds the question unless it duplicates one already in the pool. */
  tryAdd(q: Question): string | null {
    const dup = this.index.check(q);
    if (dup) return `${dup.code} (${dup.otherId})`;
    this.insert(q);
    return null;
  }

  /**
   * Facts the generator must avoid: the semantic keys / answers of
   * everything in the pool for this section plus anything the client has
   * already used (matched through its semantic fingerprints).
   */
  avoidList(c: Category, clientFingerprints: string[] = []): string[] {
    const out = new Set<string>();
    for (const q of this.byCategory(c)) out.add(`${q.semantic_key} → ${q.answer}`);
    for (const fp of clientFingerprints) {
      const e = this.index.bySemanticFp(fp);
      if (e) out.add(`${e.semanticKey} → ${e.answer}`);
    }
    return [...out];
  }

  /** Questions of a section the client has not seen yet. */
  available(c: Category, excludeFingerprints: Iterable<string>): Question[] {
    const ex = new Set(excludeFingerprints);
    return this.byCategory(c).filter((q) => !ex.has(q.semantic_fp!) && !ex.has(q.text_fp!) && !ex.has(q.id));
  }

  save(): void {
    if (!this.file) return;
    mkdirSync(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify({ version: 1, updated_at: new Date().toISOString(), questions: this.all() }, null, 1));
    renameSync(tmp, this.file);
  }
}
