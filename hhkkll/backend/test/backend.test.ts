import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { describe, it } from "node:test";
import { collectRetrievedUrls, extractTagged, normalizeUrl } from "../src/anthropic.js";
import { Budget, BudgetExceededError, costOf, pricesFromEnv, RateLimiter } from "../src/budget.js";
import { contentTokens, DedupIndex, normalizeAnswer, normalizeText, semanticFingerprint, textFingerprint, textSimilarity, trigrams } from "../src/dedup.js";
import { generateBatch } from "../src/pipeline.js";
import { startServer } from "../src/server.js";
import { QuestionStore } from "../src/store.js";
import type { CallUsage, Candidate, Category, GenerateRequest, GenerateResult, Question, QuestionProvider, VerifyResult } from "../src/types.js";

const repo = new URL("../../../", import.meta.url); // dist/test → hhkkll/

const usage = (): CallUsage => ({ inputTokens: 20000, outputTokens: 3000, cacheReadTokens: 0, cacheWriteTokens: 0, webSearches: 5, webFetches: 0 });

/** A provider whose answers are scripted, so the pipeline rules can be tested without spending money. */
class ScriptedProvider implements QuestionProvider {
  readonly name = "scripted";
  generateCalls: GenerateRequest[] = [];
  verifyCalls: Candidate[][] = [];
  constructor(
    private readonly gen: (req: GenerateRequest) => GenerateResult,
    private readonly ver: (cands: Candidate[]) => VerifyResult,
  ) {}
  async generate(req: GenerateRequest) {
    this.generateCalls.push(req);
    return this.gen(req);
  }
  async verify(_c: Category, cands: Candidate[]) {
    this.verifyCalls.push(cands);
    return this.ver(cands);
  }
}

const cand = (n: number, url = `https://en.wikipedia.org/wiki/Page_${n}`) => ({
  difficulty: "very_expert",
  question: `سؤال اختباري رقم ${n} عن نهائي بطولة مختلفة تماماً ${n}`,
  answer: `إجابة ${n}`,
  accepted_answers: [`Answer ${n}`],
  items: [],
  clues: [],
  topic: "test",
  semantic_key: `test-fact-${n}`,
  sources: [{ title: `Page ${n}`, url }],
});

describe("dedup parity with the Dart engine", () => {
  const vectors = JSON.parse(readFileSync(new URL("core/test/fixtures/normalize_vectors.json", repo), "utf8")) as {
    vectors: { input: string; normalized: string; tokens: string[]; answer: string; trigram_count: number }[];
    pairs: { a: number; b: number; similarity: number }[];
  };
  it("normalises exactly like Dart", () => {
    for (const v of vectors.vectors) {
      assert.equal(normalizeText(v.input), v.normalized, v.input);
      assert.deepEqual(contentTokens(v.input), v.tokens, v.input);
      assert.equal(normalizeAnswer(v.input), v.answer, v.input);
      assert.equal(trigrams(v.input).size, v.trigram_count, v.input);
    }
  });
  it("computes the same similarity", () => {
    for (const p of vectors.pairs) {
      const a = vectors.vectors[p.a]!.input;
      const b = vectors.vectors[p.b]!.input;
      assert.ok(Math.abs(textSimilarity(a, b) - p.similarity) < 1e-9);
    }
  });
  it("computes the same fingerprints for the starter pack as the Dart app", () => {
    // The Dart test suite writes nothing; fingerprints are checked through
    // the store which adds text_fp/semantic_fp exactly like Question.toJson.
    const seed = JSON.parse(readFileSync(new URL("content/seed_questions.json", repo), "utf8")) as { questions: Question[] };
    const idx = new DedupIndex();
    for (const q of seed.questions) {
      assert.equal(idx.tryAdd(q), null, `seed duplicate: ${q.id}`);
      assert.match(textFingerprint(q), /^[0-9a-f]{20}$/);
      assert.match(semanticFingerprint(q), /^[0-9a-f]{20}$/);
    }
  });
  it("detects a re-worded duplicate", () => {
    const base = { category: "wdyk" as const, difficulty: "expert" as const, accepted_answers: [], topic: "", sources: [{ title: "", url: "https://x.org" }], created_at: "", verification: { status: "verified" as const, method: "" }, origin: "server" as const, semantic_key: "" };
    const idx = new DedupIndex();
    idx.addQuestion({ ...base, id: "1", question: "من سجّل هدف إسبانيا الوحيد في نهائي كأس العالم 2010 أمام هولندا؟", answer: "أندريس إنييستا" });
    const r = idx.check({ ...base, id: "2", question: "نهائي كأس العالم 2010 بين إسبانيا وهولندا حُسم بهدف وحيد، من صاحبه؟", answer: "أندريس إنييستا" });
    assert.equal(r?.code, "same-answer-similar-question");
  });
});

describe("helpers", () => {
  it("collects retrieved URLs from nested result blocks", () => {
    const urls = collectRetrievedUrls([
      { type: "server_tool_use", input: { query: "x" } },
      { type: "web_search_tool_result", content: [{ type: "web_search_result", url: "https://EN.wikipedia.org/wiki/A#x", title: "A" }] },
      { type: "text", text: "...", citations: [{ type: "web_search_result_location", url: "https://www.uefa.com/b/" }] },
      { type: "web_fetch_tool_result", content: { type: "web_fetch_result", url: "https://en.m.wikipedia.org/wiki/C" } },
    ]);
    assert.deepEqual([...urls].sort(), ["https://en.wikipedia.org/wiki/A", "https://en.wikipedia.org/wiki/C", "https://uefa.com/b"]);
  });
  it("normalises URLs", () => {
    assert.equal(normalizeUrl("https://en.wikipedia.org/wiki/Lu%C3%ADs_Figo"), normalizeUrl("https://en.wikipedia.org/wiki/Luís_Figo"));
  });
  it("extracts tagged JSON", () => {
    assert.deepEqual(extractTagged("research...\n<questions>\n```json\n[{\"a\":1}]\n```\n</questions>", "questions"), [{ a: 1 }]);
  });
  it("prices a call", () => {
    const c = costOf(usage(), pricesFromEnv({}));
    // 20k in × $4/M + 3k out × $20/M + 5 searches × $0.01
    assert.ok(Math.abs(c - (0.08 + 0.06 + 0.05)) < 1e-9);
  });
});

describe("generation pipeline", () => {
  const ok = (n: number) => new ScriptedProvider(
    () => ({ candidates: Array.from({ length: n }, (_, i) => cand(i)), retrievedUrls: new Set(Array.from({ length: n }, (_, i) => normalizeUrl(`https://en.wikipedia.org/wiki/Page_${i}`))), usage: usage(), model: "m" }),
    (cs) => ({ verdicts: cs.map((_, index) => ({ index, verdict: "verified", evidence_urls: [`https://uefa.com/e${index}`] })), retrievedUrls: new Set(cs.map((_, i) => `https://uefa.com/e${i}`)), usage: usage(), model: "m" }),
  );

  it("accepts verified questions with retrieved sources and records cost", async () => {
    const store = new QuestionStore();
    const budget = new Budget(10, 10, pricesFromEnv({}));
    const r = await generateBatch(ok(4), store, budget, "wdyk", 4);
    assert.equal(r.accepted.length, 4);
    assert.equal(store.size, 4);
    for (const q of r.accepted) {
      assert.equal(q.verification.status, "verified");
      assert.equal(q.verification.method, "ai-independent-web-verification");
      assert.equal(q.sources.length, 2);
    }
    assert.ok(Math.abs(r.costUsd - 0.38) < 1e-9);
  });

  it("rejects invented sources, failed verification, unretrieved evidence and duplicates", async () => {
    const store = new QuestionStore();
    const budget = new Budget(10, 10, pricesFromEnv({}));
    await generateBatch(ok(1), store, budget, "wdyk", 1); // seeds cand(0)
    const p = new ScriptedProvider(
      () => ({
        candidates: [cand(0), cand(1), cand(2, "https://invented.example/page"), cand(3), cand(4), { question: "broken" }],
        retrievedUrls: new Set([0, 1, 3, 4].map((i) => normalizeUrl(`https://en.wikipedia.org/wiki/Page_${i}`))),
        usage: usage(),
        model: "m",
      }),
      () => ({
        verdicts: [
          { index: 0, verdict: "rejected", problems: "wrong year", evidence_urls: [] },
          { index: 1, verdict: "verified", evidence_urls: ["https://not-retrieved.org/x"] },
          { index: 2, verdict: "verified", evidence_urls: ["https://uefa.com/ok"] },
        ],
        retrievedUrls: new Set(["https://uefa.com/ok"]),
        usage: usage(),
        model: "m",
      }),
    );
    const r = await generateBatch(p, store, budget, "wdyk", 6);
    const reasons = r.rejected.map((x) => x.reason).join(" | ");
    assert.equal(r.accepted.length, 1);
    assert.equal(r.accepted[0]!.semantic_key, "test-fact-4");
    assert.match(reasons, /duplicate/);
    assert.match(reasons, /was actually retrieved by the generator/);
    assert.match(reasons, /verifier: rejected/);
    assert.match(reasons, /evidence was not actually retrieved/);
    assert.match(reasons, /schema/);
    // The verifier only saw the 3 candidates that survived the cheap checks.
    assert.equal(p.verifyCalls[0]!.length, 3);
    // The generator was told what to avoid.
    assert.ok(p.generateCalls[0]!.avoid.some((a) => a.startsWith("test-fact-0")));
  });

  it("rejects auctions whose items could not all be confirmed", async () => {
    const auction = { ...cand(7), items: [{ name: "a" }, { name: "b" }, { name: "c" }] };
    const p = new ScriptedProvider(
      () => ({ candidates: [auction], retrievedUrls: new Set([normalizeUrl(auction.sources[0]!.url)]), usage: usage(), model: "m" }),
      () => ({ verdicts: [{ index: 0, verdict: "verified", evidence_urls: ["https://e.org/1"], unconfirmed_items: ["c"] }], retrievedUrls: new Set(["https://e.org/1"]), usage: usage(), model: "m" }),
    );
    const r = await generateBatch(p, new QuestionStore(), new Budget(10, 10, pricesFromEnv({})), "auction", 1);
    assert.equal(r.accepted.length, 0);
    assert.match(r.rejected[0]!.reason, /unconfirmed auction items/);
  });

  it("refuses to call the model once the budget is spent", async () => {
    const budget = new Budget(0.5, 100, pricesFromEnv({}));
    const p = ok(2);
    await assert.rejects(generateBatch(p, new QuestionStore(), budget, "buzzer", 2, [], { estimatePerCallUsd: 0.6 }), BudgetExceededError);
    assert.equal(p.generateCalls.length, 0);
  });
});

describe("rate limiter", () => {
  it("allows a burst then throttles", () => {
    let t = 0;
    const rl = new RateLimiter(3, () => t);
    assert.ok(rl.allow("a") && rl.allow("a") && rl.allow("a"));
    assert.equal(rl.allow("a"), false);
    assert.ok(rl.allow("b"));
    t += 20000;
    assert.ok(rl.allow("a"));
  });
});

describe("HTTP API", () => {
  it("serves unseen questions and generates in the background when low", async () => {
    const store = new QuestionStore();
    let n = 100;
    const p = new ScriptedProvider(
      () => {
        const cs = [cand(n++), cand(n++)];
        return { candidates: cs, retrievedUrls: new Set(cs.map((c) => normalizeUrl(c.sources[0]!.url))), usage: usage(), model: "m" };
      },
      (cs) => ({ verdicts: cs.map((_, index) => ({ index, verdict: "verified", evidence_urls: ["https://e.org"] })), retrievedUrls: new Set(["https://e.org"]), usage: usage(), model: "m" }),
    );
    const server = startServer({ provider: p, store, budget: new Budget(10, 10, pricesFromEnv({})), limiter: new RateLimiter(100), batchSize: 2, lowWatermark: 2, log: () => {} }, 0);
    const port = (server.address() as AddressInfo).port;
    const post = async (exclude: string[]) => {
      const r = await fetch(`http://127.0.0.1:${port}/v1/questions`, { method: "POST", body: JSON.stringify({ category: "buzzer", count: 5, exclude }) });
      return (await r.json()) as { questions: Question[]; generating: boolean };
    };
    try {
      const first = await post([]);
      assert.equal(first.questions.length, 0);
      assert.equal(first.generating, true);
      await new Promise((r) => setTimeout(r, 50));
      const second = await post([]);
      assert.equal(second.questions.length, 2);
      const seen = second.questions.map((q) => q.semantic_fp!);
      await new Promise((r) => setTimeout(r, 50));
      const third = await post(seen);
      assert.ok(third.questions.length > 0);
      assert.ok(third.questions.every((q) => !seen.includes(q.semantic_fp!)), "never re-serves excluded questions");
      const health = (await (await fetch(`http://127.0.0.1:${port}/health`)).json()) as { generation_enabled: boolean; spent_today_usd: number };
      assert.equal(health.generation_enabled, true);
      assert.ok(health.spent_today_usd > 0);
      const bad = await fetch(`http://127.0.0.1:${port}/v1/questions`, { method: "POST", body: JSON.stringify({ category: "nope" }) });
      assert.equal(bad.status, 400);
    } finally {
      server.close();
    }
  });
});
