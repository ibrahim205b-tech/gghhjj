import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { AnthropicProvider } from "./anthropic.js";
import { Budget, BudgetExceededError, pricesFromEnv, RateLimiter } from "./budget.js";
import { generateBatch } from "./pipeline.js";
import { QuestionStore } from "./store.js";
import { CATEGORIES, type Category, type QuestionProvider } from "./types.js";

export interface ServerDeps {
  provider: QuestionProvider | null;
  store: QuestionStore;
  budget: Budget;
  limiter: RateLimiter;
  batchSize: number;
  /** Generate in the background when fewer than this many are unseen. */
  lowWatermark: number;
  log?: (m: string) => void;
}

/**
 * HTTP API used by the app.
 *   GET  /health
 *   POST /v1/questions  {category, count, exclude: [semantic fingerprints]}
 *        → {questions: [...], generating: bool}
 * When a client is running low on unseen questions the server starts a
 * background generation batch for that section (one at a time per
 * section, within the budget). The client simply asks again later.
 */
export function createApp(deps: ServerDeps) {
  const inflight = new Map<Category, Promise<void>>();
  const lastError = new Map<Category, string>();
  const log = deps.log ?? ((m: string) => console.log(m));

  const kick = (c: Category, fps: string[]) => {
    if (!deps.provider || inflight.has(c)) return;
    const p = generateBatch(deps.provider, deps.store, deps.budget, c, deps.batchSize, fps, { log })
      .then(() => {
        deps.store.save();
        lastError.delete(c);
      })
      .catch((e: unknown) => {
        const msg = e instanceof BudgetExceededError ? `budget: ${e.message}` : String(e);
        lastError.set(c, msg);
        log(`[${c}] generation failed: ${msg}`);
      })
      .finally(() => inflight.delete(c));
    inflight.set(c, p);
  };

  const send = (res: ServerResponse, status: number, body: unknown) => {
    res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    res.end(JSON.stringify(body));
  };

  const readBody = (req: IncomingMessage) =>
    new Promise<string>((resolve, reject) => {
      let data = "";
      req.setEncoding("utf8");
      req.on("data", (ch: string) => {
        data += ch;
        if (data.length > 512 * 1024) reject(new Error("body too large"));
      });
      req.on("end", () => resolve(data));
      req.on("error", reject);
    });

  const handler = async (req: IncomingMessage, res: ServerResponse) => {
    const ip = (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0]?.trim() ?? req.socket.remoteAddress ?? "?";
    if (!deps.limiter.allow(ip)) return send(res, 429, { error: "rate limited" });
    const url = new URL(req.url ?? "/", "http://x");
    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return send(res, 200, {
          ok: true,
          generation_enabled: deps.provider !== null,
          pool: Object.fromEntries(CATEGORIES.map((c) => [c, deps.store.byCategory(c).length])),
          generating: [...inflight.keys()],
          spent_today_usd: Number(deps.budget.todayUsd.toFixed(4)),
          daily_budget_usd: deps.budget.dailyLimitUsd,
          errors: Object.fromEntries(lastError),
        });
      }
      if (req.method === "POST" && url.pathname === "/v1/questions") {
        const body = JSON.parse((await readBody(req)) || "{}") as { category?: string; count?: number; exclude?: unknown };
        const c = body.category as Category;
        if (!CATEGORIES.includes(c)) return send(res, 400, { error: "bad category" });
        const count = Math.max(1, Math.min(20, Number(body.count) || 6));
        const exclude = Array.isArray(body.exclude) ? body.exclude.filter((x): x is string => typeof x === "string").slice(0, 5000) : [];
        const avail = deps.store.available(c, exclude);
        // Newest first so long-running clients keep getting fresh material.
        avail.sort((a, b) => b.created_at.localeCompare(a.created_at));
        const out = avail.slice(0, count);
        if (avail.length - out.length < deps.lowWatermark) kick(c, exclude);
        return send(res, 200, { questions: out, generating: inflight.has(c), error: lastError.get(c) ?? null });
      }
      return send(res, 404, { error: "not found" });
    } catch (e) {
      return send(res, 400, { error: String(e) });
    }
  };

  return { handler, inflight };
}

export function startServer(deps: ServerDeps, port: number): Server {
  const app = createApp(deps);
  const server = createServer((req, res) => void app.handler(req, res));
  server.listen(port);
  return server;
}

// Entry point: `node dist/src/server.js`
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
  const dataDir = env.DATA_DIR ?? "data";
  const store = new QuestionStore(join(dataDir, "questions.json"));
  const provider = env.ANTHROPIC_API_KEY || env.ANTHROPIC_AUTH_TOKEN
    ? new AnthropicProvider({ model: env.HHKKLL_MODEL })
    : null;
  if (!provider) console.warn("No ANTHROPIC_API_KEY: serving the existing pool only, generation disabled.");
  const port = Number(env.PORT ?? 8080);
  startServer(
    {
      provider,
      store,
      budget: new Budget(Number(env.DAILY_BUDGET_USD ?? 3), Number(env.RUN_BUDGET_USD ?? 1e9), pricesFromEnv(), join(dataDir, "budget.json")),
      limiter: new RateLimiter(Number(env.RATE_PER_MINUTE ?? 60)),
      batchSize: Number(env.BATCH_SIZE ?? 6),
      lowWatermark: Number(env.LOW_WATERMARK ?? 6),
    },
    port,
  );
  console.log(`HHKKLL question service on :${port} (pool ${store.size})`);
}
