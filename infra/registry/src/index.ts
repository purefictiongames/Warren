import { Hono } from "hono";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";
import { env } from "./env.js";
import { auth } from "./routes/auth.js";
import { usage } from "./routes/usage.js";
import { rpc, registerModule } from "./routes/rpc.js";
import { layoutModule } from "./modules/layout.js";
import { mapgenModule } from "./modules/mapgen.js";
import { worldModule } from "./modules/world.js";
import { poolRoutes } from "./routes/pool.js";

const app = new Hono();

app.use("*", logger());

// Health check
app.get("/health", (c) => c.json({ status: "ok" }));

// API routes
app.route("/v1/auth", auth);
app.route("/v1/usage", usage);
app.route("/v1/rpc", rpc);
app.route("/v1/pool", poolRoutes);

// --- Warren modules ---
registerModule("Layout", layoutModule);
registerModule("MapGen", mapgenModule);
registerModule("World", worldModule);

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
