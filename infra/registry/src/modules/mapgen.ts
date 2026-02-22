import { env } from "../env.js";

/**
 * Proxy module that forwards map generation RPC calls to the Lune server.
 * Returns pre-computed terrain data (splines, rooms, doors, inventory).
 * Height field is NOT included — regenerated locally on Roblox (deterministic).
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

export const mapgenModule = {
  generate: async (params: unknown) => {
    return callLune("mapgen.action.generate", params);
  },
};
