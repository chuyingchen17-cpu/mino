import { createHash, createHmac, type BinaryLike, type KeyObject } from "node:crypto";

function canonicalJSON(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(object[key])}`).join(",")}}`;
}

export function requestFingerprint(value: unknown): string {
  return createHash("sha256").update(canonicalJSON(value), "utf8").digest("hex");
}

export function keyedRequestFingerprint(value: unknown, key: BinaryLike | KeyObject): string {
  return `hmac-sha256:${createHmac("sha256", key)
    .update("mino-request-fingerprint-v1\0", "utf8")
    .update(canonicalJSON(value), "utf8")
    .digest("hex")}`;
}
