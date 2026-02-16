import { Hono } from "hono";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";
import { env } from "./env.js";
import { auth } from "./routes/auth.js";
import { usage } from "./routes/usage.js";

const app = new Hono();

app.use("*", logger());

// Health check
app.get("/health", (c) => c.json({ status: "ok" }));

// API routes
app.route("/v1/auth", auth);
app.route("/v1/usage", usage);

// 404 fallback
app.notFound((c) =>
  c.json({ error: "not_found", path: c.req.path }, 404)
);

// Error handler
app.onError((err, c) => {
  console.error("Unhandled error:", err);
  return c.json({ error: "internal_error" }, 500);
});

serve({ fetch: app.fetch, port: env.port }, (info) => {
  console.log(`Warren Registry listening on :${info.port}`);
});
