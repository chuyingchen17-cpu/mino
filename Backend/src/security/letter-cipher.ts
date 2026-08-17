import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { AppError } from "../errors.js";
import { keyedRequestFingerprint } from "./request-fingerprint.js";

const PREFIX = "mino:aesgcm:v1";

export class LetterCipher {
  constructor(private readonly key: Buffer) {
    if (key.length !== 32) throw new Error("Letter encryption key must be exactly 32 bytes");
  }

  encrypt(plaintext: string): string {
    const nonce = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, nonce);
    const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [PREFIX, nonce.toString("base64url"), tag.toString("base64url"), ciphertext.toString("base64url")].join(":");
  }

  decrypt(value: string): string {
    if (!value.startsWith(`${PREFIX}:`)) return value; // Read-only compatibility for pre-encryption local MVP rows.
    const parts = value.split(":");
    if (parts.length !== 6) throw new AppError(500, "letter_decryption_failed", "The stored letter could not be decrypted");
    try {
      const nonce = Buffer.from(parts[3]!, "base64url");
      const tag = Buffer.from(parts[4]!, "base64url");
      const ciphertext = Buffer.from(parts[5]!, "base64url");
      const decipher = createDecipheriv("aes-256-gcm", this.key, nonce);
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
    } catch {
      throw new AppError(500, "letter_decryption_failed", "The stored letter could not be decrypted");
    }
  }

  fingerprint(value: unknown): string {
    return keyedRequestFingerprint(value, this.key);
  }

  static fromBase64(encoded: string): LetterCipher {
    const key = Buffer.from(encoded, "base64");
    if (key.length !== 32 || key.toString("base64").replace(/=+$/, "") !== encoded.trim().replace(/=+$/, "")) {
      throw new Error("LETTER_ENCRYPTION_KEY must be valid base64 encoding exactly 32 bytes");
    }
    return new LetterCipher(key);
  }

  static development(databaseURL: string): LetterCipher {
    return new LetterCipher(createHash("sha256").update(`mino-development-letter-key:${databaseURL}`).digest());
  }
}
