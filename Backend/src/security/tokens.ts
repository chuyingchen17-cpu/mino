const encoder = new TextEncoder();

export function randomToken(byteCount = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteCount));
  return base64URL(bytes);
}

export async function hashToken(token: string, pepper: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(`${pepper}:${token}`));
  return base64URL(new Uint8Array(digest));
}

export function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

export function fromBase64URL(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
