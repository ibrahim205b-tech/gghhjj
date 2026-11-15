import { z } from "zod";

export const CATEGORIES = ["auction", "wdyk", "buzzer", "whoami"] as const;
export type Category = (typeof CATEGORIES)[number];

export const DIFFICULTIES = ["hard", "expert", "very_expert", "historic", "impossible"] as const;

export const SourceSchema = z.object({ title: z.string().default(""), url: z.string().url() });
export type Source = z.infer<typeof SourceSchema>;

export const AuctionItemSchema = z.object({
  name: z.string().min(1),
  aliases: z.array(z.string()).default([]),
});

/** What the AI generator must return for each question. */
export const CandidateSchema = z.object({
  difficulty: z.enum(DIFFICULTIES),
  question: z.string().min(1),
  answer: z.string().min(1),
  accepted_answers: z.array(z.string()).default([]),
  items: z.array(AuctionItemSchema).default([]),
  items_exhaustive: z.boolean().default(false),
  clues: z.array(z.string()).default([]),
  topic: z.string().default(""),
  semantic_key: z.string().min(3),
  fact_as_of: z.string().optional(),
  sources: z.array(SourceSchema).min(1),
});
export type Candidate = z.infer<typeof CandidateSchema>;

export const VerdictSchema = z.object({
  index: z.number().int().nonnegative(),
  verdict: z.enum(["verified", "rejected", "uncertain"]),
  problems: z.string().default(""),
  evidence_urls: z.array(z.string()).default([]),
  /** For auction questions: item names the verifier could not confirm. */
  unconfirmed_items: z.array(z.string()).default([]),
});
export type Verdict = z.infer<typeof VerdictSchema>;

export interface Verification {
  status: "verified" | "curated";
  method: string;
  model?: string;
  checked_at?: string;
  notes?: string;
}

/** Wire format shared with the app (see core/lib/src/question.dart). */
export interface Question {
  id: string;
  category: Category;
  difficulty: (typeof DIFFICULTIES)[number];
  question: string;
  answer: string;
  accepted_answers: string[];
  items?: { name: string; aliases: string[] }[];
  items_exhaustive?: boolean;
  clues?: string[];
  topic: string;
  semantic_key: string;
  sources: Source[];
  fact_as_of?: string;
  created_at: string;
  verification: Verification;
  origin: "seed" | "server" | "feed";
  text_fp?: string;
  semantic_fp?: string;
}

/** Validation identical to Question.validate() in Dart. */
export function validateQuestion(q: Question): string[] {
  const p: string[] = [];
  if (!q.id.trim()) p.push("empty id");
  if (q.question.trim().length < 8 && q.category !== "whoami") p.push("question text too short");
  if (!q.answer.trim()) p.push("empty answer");
  if (q.sources.length === 0) p.push("no source");
  for (const s of q.sources) {
    try {
      const u = new URL(s.url);
      if (!(u.protocol === "https:" || u.protocol === "http:") || !u.host) p.push(`bad source url "${s.url}"`);
    } catch {
      p.push(`bad source url "${s.url}"`);
    }
  }
  if (q.category === "auction" && (q.items?.length ?? 0) < 3) p.push("auction needs at least 3 reference items");
  if (q.category === "whoami" && ((q.clues?.length ?? 0) < 3 || (q.clues?.length ?? 0) > 5)) {
    p.push("who-am-i needs 3 to 5 clues");
  }
  return p;
}

/** Usage of one model call, for cost accounting. */
export interface CallUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  webSearches: number;
  webFetches: number;
}

export interface GenerateRequest {
  category: Category;
  count: number;
  /** Facts already used — the generator must not ask about them again. */
  avoid: string[];
}

export interface GenerateResult {
  candidates: unknown[];
  /** Every URL the model actually retrieved through web search / fetch. */
  retrievedUrls: Set<string>;
  usage: CallUsage;
  model: string;
}

export interface VerifyResult {
  verdicts: unknown[];
  retrievedUrls: Set<string>;
  usage: CallUsage;
  model: string;
}

/** Swappable AI back end. */
export interface QuestionProvider {
  readonly name: string;
  generate(req: GenerateRequest): Promise<GenerateResult>;
  verify(category: Category, candidates: Candidate[]): Promise<VerifyResult>;
}
