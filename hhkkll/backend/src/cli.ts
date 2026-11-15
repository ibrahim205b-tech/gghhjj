// Command-line entry used by GitHub Actions.
//
//   node dist/src/cli.js generate --out <feed dir> [--per-category 6] [--max-usd 2] [--categories auction,wdyk]
//       Generates + verifies new questions and writes a static feed
//       (<out>/questions.json, <out>/<category>.json, <out>/index.json) that
//       the app downloads. Needs ANTHROPIC_API_KEY.
//
//   node dist/src/cli.js check-sources <seed_questions.json>
//       Opens every source URL of the bundled starter pack and fails if any
//       does not resolve.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AnthropicProvider } from "./anthropic.js";
import { Budget, BudgetExceededError, pricesFromEnv } from "./budget.js";
import { generateBatch } from "./pipeline.js";
import { QuestionStore } from "./store.js";
import { CATEGORIES, type Category, type Question } from "./types.js";

function arg(name: string, def?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : def;
}

export function writeFeed(store: QuestionStore, out: string): Record<string, number> {
  mkdirSync(out, { recursive: true });
  store.save();
  const counts: Record<string, number> = {};
  for (const c of CATEGORIES) {
    const qs = store.byCategory(c).map((q) => ({ ...q, origin: "feed" as const }));
    counts[c] = qs.length;
    writeFileSync(join(out, `${c}.json`), JSON.stringify({ version: 1, category: c, questions: qs }));
  }
  writeFileSync(join(out, "index.json"), JSON.stringify({ version: 1, updated_at: new Date().toISOString(), counts }, null, 1));
  return counts;
}

async function generate(): Promise<number> {
  const out = arg("out", "feed")!;
  const per = Number(arg("per-category", "6"));
  const maxUsd = Number(arg("max-usd", "2"));
  const cats = (arg("categories", CATEGORIES.join(","))!.split(",") as Category[]).filter((c) => CATEGORIES.includes(c));
  if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN) {
    console.log("ANTHROPIC_API_KEY is not configured — nothing generated (no cost incurred).");
    return 0;
  }
  const store = new QuestionStore(join(out, "questions.json"));
  const budget = new Budget(Number(process.env.DAILY_BUDGET_USD ?? maxUsd), maxUsd, pricesFromEnv());
  const provider = new AnthropicProvider({ model: process.env.HHKKLL_MODEL });
  let accepted = 0;
  for (const c of cats) {
    try {
      const r = await generateBatch(provider, store, budget, c, per, [], {
        log: (m) => console.log(m),
        estimatePerCallUsd: Number(process.env.ESTIMATE_PER_CALL_USD ?? 0.8),
      });
      accepted += r.accepted.length;
    } catch (e) {
      if (e instanceof BudgetExceededError) {
        console.log(`Budget cap: ${e.message}`);
        break;
      }
      console.error(`[${c}] failed: ${String(e)}`);
    }
  }
  const counts = writeFeed(store, out);
  console.log(`accepted ${accepted} new questions; spent $${budget.spentThisRun.toFixed(3)} in ${budget.calls} calls; feed: ${JSON.stringify(counts)}`);
  return 0;
}

async function checkSources(file: string): Promise<number> {
  const j = JSON.parse(readFileSync(file, "utf8")) as { questions: Question[] };
  const urls = [...new Set(j.questions.flatMap((q) => q.sources.map((s) => s.url)))];
  let bad = 0;
  for (const url of urls) {
    let status = 0;
    for (let attempt = 0; attempt < 3 && status !== 200; attempt++) {
      try {
        const r = await fetch(url, { redirect: "follow", headers: { "user-agent": "HHKKLL-source-check/1.0 (CI)" } });
        status = r.status;
      } catch {
        status = -1;
      }
      if (status !== 200) await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    }
    console.log(`${status === 200 ? "OK " : "BAD"} ${status} ${url}`);
    if (status !== 200) bad++;
  }
  console.log(`${urls.length - bad}/${urls.length} source URLs resolve`);
  return bad === 0 ? 0 : 1;
}

const cmd = process.argv[2];
const run = cmd === "generate" ? generate() : cmd === "check-sources" ? checkSources(process.argv[3] ?? "") : Promise.resolve(2);
run.then((code) => {
  if (code === 2) console.error("usage: cli.js generate|check-sources ...");
  process.exitCode = code;
});
