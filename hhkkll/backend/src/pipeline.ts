import { createHash } from "node:crypto";
import { normalizeUrl } from "./anthropic.js";
import { Budget } from "./budget.js";
import type { QuestionStore } from "./store.js";
import {
  CandidateSchema,
  type Candidate,
  type Category,
  type Question,
  type QuestionProvider,
  type Source,
  VerdictSchema,
  validateQuestion,
} from "./types.js";

export interface BatchReport {
  category: Category;
  generated: number;
  accepted: Question[];
  rejected: { question: string; reason: string }[];
  costUsd: number;
}

export interface PipelineOptions {
  /** Pessimistic cost of one model call, checked before calling. */
  estimatePerCallUsd?: number;
  log?: (msg: string) => void;
  now?: () => Date;
}

const idFor = (category: Category, c: Candidate) =>
  `srv-${category}-${createHash("sha1").update(`${c.semantic_key}|${c.question}|${c.answer}`).digest("hex").slice(0, 16)}`;

const hostTitle = (url: string) => {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
};

/**
 * Generates one batch for a section and returns only questions that
 *  1. parse against the schema,
 *  2. cite at least one page the generator actually retrieved,
 *  3. are not duplicates of anything in the pool,
 *  4. were confirmed by an independent verification call whose evidence
 *     URLs were actually retrieved by that call.
 * Everything else is rejected with a reason. Nothing is ever marked
 * "verified" without step 4.
 */
export async function generateBatch(
  provider: QuestionProvider,
  store: QuestionStore,
  budget: Budget,
  category: Category,
  count: number,
  clientFingerprints: string[] = [],
  opts: PipelineOptions = {},
): Promise<BatchReport> {
  const log = opts.log ?? (() => {});
  const now = opts.now ?? (() => new Date());
  const est = opts.estimatePerCallUsd ?? 1.0;
  const report: BatchReport = { category, generated: 0, accepted: [], rejected: [], costUsd: 0 };
  const reject = (question: string, reason: string) => {
    report.rejected.push({ question, reason });
    log(`  ✗ ${reason}: ${question.slice(0, 80)}`);
  };

  budget.assertCanSpend(est);
  const gen = await provider.generate({ category, count, avoid: store.avoidList(category, clientFingerprints) });
  report.costUsd += budget.record(gen.usage);
  report.generated = gen.candidates.length;
  log(`[${category}] generated ${gen.candidates.length} candidates, ${gen.retrievedUrls.size} pages retrieved`);

  const pending: { cand: Candidate; q: Question }[] = [];
  const batchIds = new Set<string>();
  for (const raw of gen.candidates) {
    const parsed = CandidateSchema.safeParse(raw);
    const label = typeof (raw as { question?: unknown })?.question === "string" ? (raw as { question: string }).question : "?";
    if (!parsed.success) {
      reject(label, `schema: ${parsed.error.issues.map((i) => `${i.path.join(".")} ${i.message}`).join("; ")}`);
      continue;
    }
    const c = parsed.data;
    const retrievedSources = c.sources.filter((s) => gen.retrievedUrls.has(normalizeUrl(s.url)));
    if (retrievedSources.length === 0) {
      reject(c.question, "no cited source was actually retrieved by the generator");
      continue;
    }
    const q: Question = {
      id: idFor(category, c),
      category,
      difficulty: c.difficulty,
      question: category === "whoami" ? "من أنا؟" : c.question,
      answer: c.answer,
      accepted_answers: c.accepted_answers,
      ...(category === "auction" ? { items: c.items, items_exhaustive: c.items_exhaustive } : {}),
      ...(category === "whoami" ? { clues: c.clues } : {}),
      topic: c.topic,
      semantic_key: c.semantic_key,
      sources: retrievedSources,
      ...(c.fact_as_of ? { fact_as_of: c.fact_as_of } : {}),
      created_at: now().toISOString(),
      verification: { status: "verified", method: "pending" },
      origin: "server",
    };
    const problems = validateQuestion(q);
    if (problems.length) {
      reject(c.question, `invalid: ${problems.join(", ")}`);
      continue;
    }
    const dup = store.index.check(q);
    if (dup || batchIds.has(q.id)) {
      reject(c.question, `duplicate: ${dup?.code ?? "same batch"}`);
      continue;
    }
    // Also de-duplicate inside the batch itself.
    if (pending.some((p) => p.q.semantic_key === q.semantic_key)) {
      reject(c.question, "duplicate inside batch");
      continue;
    }
    batchIds.add(q.id);
    pending.push({ cand: c, q });
  }
  if (pending.length === 0) return report;

  budget.assertCanSpend(est);
  const ver = await provider.verify(category, pending.map((p) => p.cand));
  report.costUsd += budget.record(ver.usage);

  const verdicts = new Map<number, ReturnType<typeof VerdictSchema.parse>>();
  for (const raw of ver.verdicts) {
    const v = VerdictSchema.safeParse(raw);
    if (v.success) verdicts.set(v.data.index, v.data);
  }

  pending.forEach(({ cand, q }, i) => {
    const v = verdicts.get(i);
    if (!v) return reject(cand.question, "no verdict from verifier");
    if (v.verdict !== "verified") return reject(cand.question, `verifier: ${v.verdict} — ${v.problems}`);
    const evidence = v.evidence_urls.filter((u) => ver.retrievedUrls.has(normalizeUrl(u)));
    if (evidence.length === 0) return reject(cand.question, "verifier evidence was not actually retrieved");
    if (category === "auction" && v.unconfirmed_items.length > 0) {
      return reject(cand.question, `unconfirmed auction items: ${v.unconfirmed_items.join(", ")}`);
    }
    const sources: Source[] = [...q.sources];
    for (const u of evidence) {
      if (!sources.some((s) => normalizeUrl(s.url) === normalizeUrl(u))) sources.push({ title: hostTitle(u), url: u });
    }
    const final: Question = {
      ...q,
      sources,
      verification: {
        status: "verified",
        method: "ai-independent-web-verification",
        model: ver.model,
        checked_at: now().toISOString(),
        notes: `generated by ${gen.model}; independently re-checked against ${evidence.length} retrieved page(s)`,
      },
    };
    const err = store.tryAdd(final);
    if (err) return reject(cand.question, `duplicate: ${err}`);
    report.accepted.push(final);
    log(`  ✓ ${final.question === "من أنا؟" ? final.answer : final.question.slice(0, 80)}`);
  });
  log(`[${category}] accepted ${report.accepted.length}/${report.generated}, cost $${report.costUsd.toFixed(3)}`);
  return report;
}
