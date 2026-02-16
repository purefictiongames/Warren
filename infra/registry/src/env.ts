function required(name: string): string {
  const val = process.env[name];
  if (!val) throw new Error(`Missing required env var: ${name}`);
  return val;
}

export const env = {
  port: parseInt(process.env.PORT || "8100", 10),
  databaseUrl: required("DATABASE_URL"),
  redisUrl: required("REDIS_URL"),
  sessionTtl: parseInt(process.env.SESSION_TTL_SECONDS || "1800", 10),
  sessionTokenBytes: parseInt(process.env.SESSION_TOKEN_BYTES || "32", 10),
};
