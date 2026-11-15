import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { CallUsage } from "./types.js";

/** Prices in USD. Defaults: Claude Opus 5.5 list prices + web search. */
export interface Prices {
  inputPerMTok: number;
  outputPerMTok: number;
  cacheReadPerMTok: number;
  cacheWritePerMTok: number;
  per1kWebSearches: number;
}

export function pricesFromEnv(env: NodeJS.ProcessEnv = process.env): Prices {
  const n = (k: string, d: number) => (env[k] ? Number(env[k]) : d);
  return {
    inputPerMTok: n("PRICE_INPUT_PER_MTOK", 4),
    outputPerMTok: n("PRICE_OUTPUT_PER_MTOK", 20),
    cacheReadPerMTok: n("PRICE_CACHE_READ_PER_MTOK", 0.2),
    cacheWritePerMTok: n("PRICE_CACHE_WRITE_PER_MTOK", 5),
    per1kWebSearches: n("PRICE_PER_1K_WEB_SEARCHES", 10),
  };
}

export function costOf(u: CallUsage, p: Prices): number {
  return (
    (u.inputTokens * p.inputPerMTok +
      u.outputTokens * p.outputPerMTok +
      u.cacheReadTokens * p.cacheReadPerMTok +
      u.cacheWriteTokens * p.cacheWritePerMTok) /
      1_000_000 +
    (u.webSearches * p.per1kWebSearches) / 1000
  );
}

export class BudgetExceededError extends Error {}

/**
 * Hard spending caps. Spending is tracked per UTC day (persisted when a
 * file is given) and per process run. A call is refused when the money
 * already spent plus a pessimistic estimate of the next call would exceed a
 * cap.
 */
export class Budget {
  private day = "";
  private spentToday = 0;
  spentThisRun = 0;
  calls = 0;

  constructor(
    readonly dailyLimitUsd: number,
    readonly runLimitUsd: number,
    readonly prices: Prices,
    private readonly file?: string,
    private readonly now: () => Date = () => new Date(),
  ) {
    if (file && existsSync(file)) {
      try {
        const j = JSON.parse(readFileSync(file, "utf8")) as { day: string; spent: number };
        this.day = j.day;
        this.spentToday = j.spent;
      } catch {
        /* corrupted file: start fresh */
      }
    }
  }

  private rollover(): void {
    const d = this.now().toISOString().slice(0, 10);
    if (d !== this.day) {
      this.day = d;
      this.spentToday = 0;
    }
  }

  get todayUsd(): number {
    this.rollover();
    return this.spentToday;
  }

  assertCanSpend(estimateUsd: number): void {
    this.rollover();
    if (this.spentToday + estimateUsd > this.dailyLimitUsd) {
      throw new BudgetExceededError(
        `daily budget reached ($${this.spentToday.toFixed(2)} of $${this.dailyLimitUsd})`,
      );
    }
    if (this.spentThisRun + estimateUsd > this.runLimitUsd) {
      throw new BudgetExceededError(
        `run budget reached ($${this.spentThisRun.toFixed(2)} of $${this.runLimitUsd})`,
      );
    }
  }

  record(u: CallUsage): number {
    this.rollover();
    const c = costOf(u, this.prices);
    this.spentToday += c;
    this.spentThisRun += c;
    this.calls++;
    if (this.file) {
      mkdirSync(dirname(this.file), { recursive: true });
      writeFileSync(this.file, JSON.stringify({ day: this.day, spent: this.spentToday }));
    }
    return c;
  }
}

/** Simple per-key token bucket for the HTTP API. */
export class RateLimiter {
  private buckets = new Map<string, { tokens: number; at: number }>();
  constructor(
    private readonly perMinute: number,
    private readonly now: () => number = Date.now,
  ) {}

  allow(key: string): boolean {
    const t = this.now();
    const b = this.buckets.get(key) ?? { tokens: this.perMinute, at: t };
    b.tokens = Math.min(this.perMinute, b.tokens + ((t - b.at) / 60000) * this.perMinute);
    b.at = t;
    if (b.tokens < 1) {
      this.buckets.set(key, b);
      return false;
    }
    b.tokens -= 1;
    this.buckets.set(key, b);
    return true;
  }
}
