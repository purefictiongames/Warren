import { env } from "../env.js";

/**
 * Proxy module that forwards layout RPC calls to the Lune server's /rpc endpoint.
 * Returns raw data (layout + styles) — not wrapped as refs.
 */

async function callLune(action: string, payload: unknown): Promise<unknown> {
  const response = await fetch(env.luneRpcUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.luneAuthToken}`,
    },
    body: JSON.stringify({ action, payload }),
  });

  if (!response.ok) {
    throw new Error(`Lune RPC failed: ${response.status}`);
  }

  return response.json();
}

export const layoutModule = {
  generate: async (config: unknown) => {
    return callLune("layout.action.generate", { config });
  },
};
