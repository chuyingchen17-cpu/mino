import { randomBytes } from "node:crypto";
import { describe, expect, it } from "vitest";
import { LetterCipher } from "../src/security/letter-cipher.js";
import { requestFingerprint } from "../src/security/request-fingerprint.js";

describe("letter encryption", () => {
  it("uses randomized authenticated encryption and detects a wrong key", () => {
    const plaintext = "只给真正收件人看的文字";
    const cipher = LetterCipher.fromBase64(randomBytes(32).toString("base64"));
    const first = cipher.encrypt(plaintext);
    const second = cipher.encrypt(plaintext);

    expect(first).not.toBe(second);
    expect(first).not.toContain(plaintext);
    expect(cipher.decrypt(first)).toBe(plaintext);

    const otherCipher = LetterCipher.fromBase64(randomBytes(32).toString("base64"));
    expect(() => otherCipher.decrypt(first)).toThrow("stored letter could not be decrypted");
  });

  it("rejects malformed key material", () => {
    expect(() => LetterCipher.fromBase64("not-a-32-byte-base64-key"))
      .toThrow("LETTER_ENCRYPTION_KEY must be valid base64 encoding exactly 32 bytes");
  });

  it("uses a keyed fingerprint for sensitive idempotency requests", () => {
    const cipher = LetterCipher.fromBase64(randomBytes(32).toString("base64"));
    const request = { visitID: "visit-a", body: "今晚记得早点休息" };

    expect(cipher.fingerprint(request)).toBe(cipher.fingerprint(request));
    expect(cipher.fingerprint(request)).toMatch(/^hmac-sha256:[0-9a-f]{64}$/);
    expect(cipher.fingerprint(request)).not.toBe(requestFingerprint(request));
  });
});
