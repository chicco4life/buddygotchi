/**
 * Environment-driven configuration.
 */

export interface Config {
  httpHost: string;
  httpPort: number;
  staleTimeoutMs: number;
  pairingCodeTtlS: number;
  decideMinIntervalMs: number;
  stateDir: string;
  webRoot: string | null;
}

export function loadConfig(): Config {
  return {
    httpHost: env("BUDDY_HTTP_HOST", "0.0.0.0"),
    httpPort: intEnv("BUDDY_HTTP_PORT", 8080),
    staleTimeoutMs: intEnv("BUDDY_STALE_MS", 30_000),
    pairingCodeTtlS: intEnv("BUDDY_PAIRING_TTL_S", 86400),
    decideMinIntervalMs: intEnv("BUDDY_DECIDE_MIN_MS", 500),
    stateDir: env("BUDDY_STATE_DIR", defaultStateDir()),
    webRoot: process.env.BUDDY_WEB_ROOT ?? null,
  };
}

function env(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

function intEnv(key: string, fallback: number): number {
  const v = process.env[key];
  if (v === undefined) return fallback;
  const n = parseInt(v, 10);
  return Number.isNaN(n) ? fallback : n;
}

function defaultStateDir(): string {
  const home = process.env.HOME ?? process.env.USERPROFILE ?? "/tmp";
  return `${home}/.buddy-daemon`;
}
