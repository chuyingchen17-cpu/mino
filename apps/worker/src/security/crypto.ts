import { base64URL, fromBase64URL } from "./tokens";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

async function letterKey(secret: string): Promise<CryptoKey> {
  const keyBytes = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", keyBytes, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export interface SealedLetter {
  ciphertext: string;
  iv: string;
  keyVersion: 1;
}

export async function encryptLetter(plaintext: string, secret: string): Promise<SealedLetter> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await letterKey(secret),
    encoder.encode(plaintext)
  );
  return {
    ciphertext: base64URL(new Uint8Array(ciphertext)),
    iv: base64URL(iv),
    keyVersion: 1
  };
}

export async function decryptLetter(ciphertext: string, iv: string, secret: string): Promise<string> {
  const ivBytes = fromBase64URL(iv);
  const ciphertextBytes = fromBase64URL(ciphertext);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: ivBytes.buffer as ArrayBuffer },
    await letterKey(secret),
    ciphertextBytes.buffer as ArrayBuffer
  );
  return decoder.decode(plaintext);
}
