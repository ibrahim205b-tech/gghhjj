import Anthropic from "@anthropic-ai/sdk";
import type { BetaContentBlock, BetaMessageParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { CallUsage, Candidate, Category, GenerateRequest, GenerateResult, QuestionProvider, VerifyResult } from "./types.js";

export interface AnthropicOptions {
  /** Model id; the default is the current Opus. */
  model?: string;
  generateEffort?: "low" | "medium" | "high" | "xhigh" | "max";
  verifyEffort?: "low" | "medium" | "high" | "xhigh" | "max";
  maxSearchesPerCall?: number;
  maxFetchesPerCall?: number;
  client?: Anthropic;
}

const CATEGORY_BRIEF: Record<Category, string> = {
  auction: `AUCTION ("المزاد"). Each question asks how many members of a CLOSED, checkable set the player can name, e.g. "كم لاعباً تستطيع أن تسمّي ممن ...؟". Players bid on how many they can name, then name them one by one in 30 seconds, so the set must have between 5 and 40 members and must be fully listable from your sources. Put EVERY member in "items" (Arabic name + aliases including the original Latin spelling and common Arabic spellings). Set "items_exhaustive": true only if the sources give the complete list. Always bound the set in time inside the question (e.g. "حتى نهائي 2025").`,
  wdyk: `WHAT DO YOU KNOW ("ماذا تعرف؟"). Deep factual questions with ONE short, unambiguous answer (a name, a club, a number, a year, a score). Ask about details only true connoisseurs know: final scorers, coaches, transfer origins, records, line-ups, unusual statistics.`,
  buzzer: `BUZZER ("الجرس"). Fast-reaction questions: one or two short sentences, answer of 1-4 words, no multi-part answers. Hard but answerable within 10 seconds by an expert.`,
  whoami: `WHO AM I ("من أنا؟"). A riddle about ONE footballer or coach. "question" must be exactly "من أنا؟". Give 4 or 5 first-person Arabic clues in "clues", ordered from the most obscure (first) to the most revealing (last). Every clue must be a verifiable fact (clubs and years, trophies, records, transfers). The answer is the person's common Arabic name; accepted_answers holds the Latin spelling and variants.`,
};

const GENERATOR_SYSTEM = `You write questions for HHKKLL, an Arabic television-style football quiz played by real football experts.

Hard rules:
- Every fact MUST come from pages you actually open with the web_search tool in this conversation. Never rely on memory alone. If you cannot confirm a fact from a retrieved page, drop the question.
- "sources" may only contain URLs that appeared in your web_search results. Prefer stable references (Wikipedia, UEFA, FIFA, official club sites, major statistics sites).
- For anything that changes over time (records, totals, transfers, current clubs) state the reference date inside the question and in "fact_as_of" (YYYY-MM-DD).
- Difficulty must be "very_expert", "historic" or "impossible" for most questions; use "hard"/"expert" sparingly.
- Write the question, answer and clues in Modern Standard Arabic; keep foreign names recognisable and add the Latin spelling to accepted_answers.
- "semantic_key" is a short English, language-neutral key of the underlying fact, like "ucl-1999-final|winning-goal-scorer" or "person:luis-figo". Two questions about the same fact must get the same key.
- Never ask about any fact listed under "Already used".
- Vary competitions, eras, countries and question types.

Output: after your research, reply with ONLY a JSON array inside <questions></questions> tags. Each element:
{"difficulty": "...", "question": "...", "answer": "...", "accepted_answers": ["..."], "items": [{"name": "...", "aliases": ["..."]}], "items_exhaustive": false, "clues": ["..."], "topic": "...", "semantic_key": "...", "fact_as_of": "YYYY-MM-DD", "sources": [{"title": "...", "url": "https://..."}]}
Use [] for "items" and "clues" when they do not apply.`;

const VERIFIER_SYSTEM = `You are the independent fact-checker of an Arabic football quiz. You did not write these questions; assume nothing in them is true until you have confirmed it.

For each question:
1. Use web_search (and web_fetch on the cited URLs) to check the question's premise, the answer, every accepted answer, every clue (who-am-I) and every item (auction).
2. verdict = "verified" only if every claim is confirmed by pages you retrieved here AND the question has exactly one correct answer (or, for auctions, the item list is correct). Use "rejected" if anything is wrong, ambiguous or outdated, and "uncertain" if you could not confirm it.
3. evidence_urls: the URLs of retrieved pages that confirm the facts.
4. For auctions, list in unconfirmed_items any item you could not confirm belongs to the set.

Reply with ONLY a JSON array inside <verdicts></verdicts> tags:
[{"index": 0, "verdict": "verified|rejected|uncertain", "problems": "...", "evidence_urls": ["https://..."], "unconfirmed_items": []}]`;

/** Collects every URL the model actually retrieved (search results, fetched pages, citations). */
export function collectRetrievedUrls(content: unknown, into: Set<string> = new Set()): Set<string> {
  const visit = (node: unknown): void => {
    if (Array.isArray(node)) {
      node.forEach(visit);
      return;
    }
    if (!node || typeof node !== "object") return;
    const o = node as Record<string, unknown>;
    const t = o["type"];
    if (
      (t === "web_search_result" || t === "web_search_result_location" || t === "web_fetch_result" || t === "char_location") &&
      typeof o["url"] === "string"
    ) {
      into.add(normalizeUrl(o["url"] as string));
    }
    for (const v of Object.values(o)) if (v && typeof v === "object") visit(v);
  };
  visit(content);
  return into;
}

export function normalizeUrl(u: string): string {
  try {
    const x = new URL(u.trim());
    x.hash = "";
    x.host = x.host.toLowerCase().replace(/^(www\.|m\.)/, "");
    if (x.host.endsWith(".m.wikipedia.org")) x.host = x.host.replace(".m.wikipedia.org", ".wikipedia.org");
    let s = x.toString();
    if (s.endsWith("/")) s = s.slice(0, -1);
    return decodeURI(s);
  } catch {
    return u.trim();
  }
}

export function extractTagged(text: string, tag: string): unknown[] {
  const m = text.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  const body = (m?.[1] ?? text).trim().replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  const parsed: unknown = JSON.parse(body);
  if (!Array.isArray(parsed)) throw new Error(`<${tag}> is not a JSON array`);
  return parsed;
}

const emptyUsage = (): CallUsage => ({
  inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, webSearches: 0, webFetches: 0,
});

export class AnthropicProvider implements QuestionProvider {
  readonly name = "anthropic";
  private readonly client: Anthropic;
  private readonly model: string;
  private readonly opts: Required<Omit<AnthropicOptions, "client" | "model">>;

  constructor(opts: AnthropicOptions = {}) {
    // Credentials come from the environment (ANTHROPIC_API_KEY on the server
    // or in GitHub Secrets) — never from the app.
    this.client = opts.client ?? new Anthropic({ maxRetries: 3 });
    this.model = opts.model ?? "claude-opus-5-5";
    this.opts = {
      generateEffort: opts.generateEffort ?? "high",
      verifyEffort: opts.verifyEffort ?? "high",
      maxSearchesPerCall: opts.maxSearchesPerCall ?? 8,
      maxFetchesPerCall: opts.maxFetchesPerCall ?? 6,
    };
  }

  /** Runs one research conversation, resuming paused server-tool turns. */
  private async run(system: string, user: string, effort: string, withFetch: boolean) {
    const messages: BetaMessageParam[] = [{ role: "user", content: user }];
    const usage = emptyUsage();
    const retrieved = new Set<string>();
    const content: BetaContentBlock[] = [];
    let model = this.model;
    for (let turn = 0; turn < 5; turn++) {
      const stream = this.client.beta.messages.stream({
        model: this.model,
        max_tokens: 32000,
        system,
        messages,
        output_config: { effort: effort as "high" },
        tools: [
          { type: "web_search_20260209", name: "web_search", max_uses: this.opts.maxSearchesPerCall },
          ...(withFetch
            ? [{ type: "web_fetch_20260209" as const, name: "web_fetch" as const, max_uses: this.opts.maxFetchesPerCall }]
            : []),
        ],
        // A refusal on the primary model is retried on a fallback model
        // inside the same call.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
      });
      const msg = await stream.finalMessage();
      model = msg.model;
      usage.inputTokens += msg.usage.input_tokens;
      usage.outputTokens += msg.usage.output_tokens;
      usage.cacheReadTokens += msg.usage.cache_read_input_tokens ?? 0;
      usage.cacheWriteTokens += msg.usage.cache_creation_input_tokens ?? 0;
      usage.webSearches += msg.usage.server_tool_use?.web_search_requests ?? 0;
      usage.webFetches += msg.usage.server_tool_use?.web_fetch_requests ?? 0;
      collectRetrievedUrls(msg.content, retrieved);
      content.push(...msg.content);
      if (msg.stop_reason === "refusal") {
        throw new Error(`model refused (${msg.stop_details?.category ?? "unknown"})`);
      }
      if (msg.stop_reason === "pause_turn") {
        messages.push({ role: "assistant", content: msg.content });
        continue;
      }
      if (msg.stop_reason === "max_tokens") throw new Error("response truncated (max_tokens)");
      break;
    }
    const text = content
      .filter((b): b is Extract<BetaContentBlock, { type: "text" }> => b.type === "text")
      .map((b) => b.text)
      .join("");
    return { text, usage, retrieved, model };
  }

  async generate(req: GenerateRequest): Promise<GenerateResult> {
    const avoid = req.avoid.slice(-400);
    const user = [
      `Section: ${CATEGORY_BRIEF[req.category]}`,
      `Write ${req.count} new questions for this section.`,
      `Today is ${new Date().toISOString().slice(0, 10)}.`,
      avoid.length ? `Already used (do not repeat these facts, people or answer sets):\n- ${avoid.join("\n- ")}` : "Already used: none.",
    ].join("\n\n");
    const r = await this.run(GENERATOR_SYSTEM, user, this.opts.generateEffort, false);
    return { candidates: extractTagged(r.text, "questions"), retrievedUrls: r.retrieved, usage: r.usage, model: r.model };
  }

  async verify(category: Category, candidates: Candidate[]): Promise<VerifyResult> {
    const payload = candidates.map((c, index) => ({
      index,
      question: c.question,
      answer: c.answer,
      accepted_answers: c.accepted_answers,
      ...(category === "auction" ? { items: c.items.map((i) => i.name), items_exhaustive: c.items_exhaustive } : {}),
      ...(category === "whoami" ? { clues: c.clues } : {}),
      fact_as_of: c.fact_as_of,
      cited_sources: c.sources.map((s) => s.url),
    }));
    const user = `Section: ${category}. Today is ${new Date().toISOString().slice(0, 10)}.\nCheck these questions:\n${JSON.stringify(payload, null, 1)}`;
    const r = await this.run(VERIFIER_SYSTEM, user, this.opts.verifyEffort, true);
    return { verdicts: extractTagged(r.text, "verdicts"), retrievedUrls: r.retrieved, usage: r.usage, model: r.model };
  }
}
