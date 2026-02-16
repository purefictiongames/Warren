import { Hono } from "hono";
import { getCachedSession } from "../redis.js";
import { findSession } from "../db.js";

export const rpc = new Hono();

/**
 * Server-side object reference store.
 * Maps ref IDs to objects. Refs expire after 5 minutes of no access.
 */
const refStore = new Map<
  string,
  { value: unknown; expiresAt: number; sessionToken: string }
>();
const REF_TTL_MS = 5 * 60 * 1000;

function generateRefId(): string {
  return "ref_" + Math.random().toString(36).slice(2, 14);
}

function touchRef(refId: string): void {
  const entry = refStore.get(refId);
  if (entry) {
    entry.expiresAt = Date.now() + REF_TTL_MS;
  }
}

function storeRef(value: unknown, sessionToken: string): string {
  const refId = generateRefId();
  refStore.set(refId, {
    value,
    expiresAt: Date.now() + REF_TTL_MS,
    sessionToken,
  });
  return refId;
}

function getRef(
  refId: string,
  sessionToken: string
): unknown | undefined {
  const entry = refStore.get(refId);
  if (!entry) return undefined;
  if (entry.sessionToken !== sessionToken) return undefined;
  if (Date.now() > entry.expiresAt) {
    refStore.delete(refId);
    return undefined;
  }
  touchRef(refId);
  return entry.value;
}

// Periodic cleanup of expired refs (every 60s)
setInterval(() => {
  const now = Date.now();
  for (const [refId, entry] of refStore) {
    if (now > entry.expiresAt) {
      refStore.delete(refId);
    }
  }
}, 60_000);

/**
 * Resolve a session token to a gameId. Redis first, Postgres fallback.
 */
async function resolveSession(
  token: string
): Promise<{ gameId: string; tier: string; scopes: string[] } | null> {
  const cached = await getCachedSession(token);
  if (cached) {
    return {
      gameId: cached.gameId,
      tier: cached.tier,
      scopes: cached.scopes,
    };
  }

  const session = await findSession(token);
  if (session) {
    return {
      gameId: session.game_id,
      tier: session.tier,
      scopes: session.scopes,
    };
  }

  return null;
}

function extractToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = header.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] ?? null;
}

/**
 * Wrap a return value — if it's an object, store it as a ref.
 * Primitives (string, number, boolean, null) pass through directly.
 */
function wrapResult(
  value: unknown,
  sessionToken: string
): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value !== "object") return value;
  if (Array.isArray(value)) {
    // Arrays of primitives pass through; arrays of objects get wrapped
    return value.map((v) => wrapResult(v, sessionToken));
  }
  // Object → store as ref
  const refId = storeRef(value, sessionToken);
  return { _ref: refId };
}

/**
 * Module registry — server-side modules that can be called via RPC.
 * Each module is a map of method names to functions.
 *
 * This is where Warren framework logic lives. Modules are registered
 * at startup. The SDK never sees this code.
 */
const modules = new Map<string, Map<string, (...args: unknown[]) => unknown>>();

/**
 * Register a module for RPC access.
 */
export function registerModule(
  name: string,
  methods: Record<string, (...args: unknown[]) => unknown>
): void {
  const methodMap = new Map<string, (...args: unknown[]) => unknown>();
  for (const [key, fn] of Object.entries(methods)) {
    methodMap.set(key, fn);
  }
  modules.set(name, methodMap);
}

/**
 * Execute a single RPC call.
 */
function executeCall(
  call: {
    module?: string;
    method: string;
    args?: unknown[];
    target?: string;
  },
  sessionToken: string
): unknown {
  // If there's a target ref, call method on the referenced object
  if (call.target) {
    const obj = getRef(call.target, sessionToken);
    if (obj === undefined) {
      throw new Error(`ref_not_found: ${call.target}`);
    }
    // Try to call the method on the object
    const target = obj as Record<string, unknown>;
    const method = target[call.method];
    if (typeof method === "function") {
      return method.apply(target, call.args ?? []);
    }
    // Maybe it's a property access (no args)
    if (call.method in target && (!call.args || call.args.length === 0)) {
      return target[call.method];
    }
    throw new Error(`method_not_found: ${call.method} on ref ${call.target}`);
  }

  // Module-level call
  if (!call.module) {
    throw new Error("module or target is required");
  }
  const mod = modules.get(call.module);
  if (!mod) {
    throw new Error(`module_not_found: ${call.module}`);
  }
  const method = mod.get(call.method);
  if (!method) {
    throw new Error(`method_not_found: ${call.module}.${call.method}`);
  }

  // Unwrap any ref args
  const args = (call.args ?? []).map((arg) => {
    if (
      arg !== null &&
      typeof arg === "object" &&
      "_ref" in (arg as Record<string, unknown>)
    ) {
      const resolved = getRef(
        (arg as { _ref: string })._ref,
        sessionToken
      );
      if (resolved === undefined) {
        throw new Error(
          `arg_ref_not_found: ${(arg as { _ref: string })._ref}`
        );
      }
      return resolved;
    }
    return arg;
  });

  return method(...args);
}

/**
 * POST /v1/rpc
 * Body: { module?: string, method: string, args?: any[], target?: string }
 * Returns: { value: any }
 */
rpc.post("/", async (c) => {
  const token = extractToken(c.req.header("Authorization"));
  if (!token) return c.json({ error: "missing_token" }, 401);

  const session = await resolveSession(token);
  if (!session) return c.json({ error: "session_not_found" }, 401);

  const call = await c.req.json<{
    module?: string;
    method: string;
    args?: unknown[];
    target?: string;
  }>();

  try {
    const rawResult = executeCall(call, token);
    const value = wrapResult(rawResult, token);
    return c.json({ value });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return c.json({ error: "rpc_error", detail: message }, 400);
  }
});

/**
 * POST /v1/rpc/batch
 * Body: { calls: [{ module?, method, args?, target? }] }
 * Returns: { results: [any] }
 */
rpc.post("/batch", async (c) => {
  const token = extractToken(c.req.header("Authorization"));
  if (!token) return c.json({ error: "missing_token" }, 401);

  const session = await resolveSession(token);
  if (!session) return c.json({ error: "session_not_found" }, 401);

  const body = await c.req.json<{
    calls: Array<{
      module?: string;
      method: string;
      args?: unknown[];
      target?: string;
    }>;
  }>();

  if (!body.calls || !Array.isArray(body.calls)) {
    return c.json({ error: "calls array is required" }, 400);
  }

  const results: unknown[] = [];
  for (const call of body.calls) {
    try {
      const rawResult = executeCall(call, token);
      results.push(wrapResult(rawResult, token));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      results.push({ _error: message });
    }
  }

  return c.json({ results });
});
