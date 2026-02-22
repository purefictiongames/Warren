import { env } from "../env.js";

/**
 * Proxy module that forwards world management RPC calls to the Lune server.
 * Wraps MapGen + Chunker: create world, get chunks, destroy world.
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

export const worldModule = {
  create: async (params: unknown) => {
    return callLune("world.action.create", params);
  },
  getChunks: async (params: unknown) => {
    return callLune("world.action.getChunks", params);
  },
  destroy: async (params: unknown) => {
    return callLune("world.action.destroy", params);
  },
};
