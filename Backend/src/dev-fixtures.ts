import { createHash } from "node:crypto";
import type { DevProfile } from "./domain.js";

export const DEV_IDS = {
  friendship: "00000000-0000-4000-8000-000000000001",
  // The legacy storage scope intentionally shares the friendship identifier.
  couple: "00000000-0000-4000-8000-000000000001",
  aliceAccount: "00000000-0000-4000-8000-00000000000a",
  bobAccount: "00000000-0000-4000-8000-00000000000b",
  charlieAccount: "00000000-0000-4000-8000-00000000000c",
  alicePet: "00000000-0000-4000-8000-0000000000a1",
  bobPet: "00000000-0000-4000-8000-0000000000b1",
  charliePet: "00000000-0000-4000-8000-0000000000c1"
} as const;

// Public, deterministic local-development credentials. Production startup rejects
// dev bootstrap and PostgresMinoStore can explicitly reject these tokens.
const ALICE_TOKEN = "mino-local-development-alice-v1";
const BOB_TOKEN = "mino-local-development-bob-v1";
const CHARLIE_TOKEN = "mino-local-development-charlie-v1";

export function isDevBootstrapToken(token: string): boolean {
  return token === ALICE_TOKEN || token === BOB_TOKEN || token === CHARLIE_TOKEN;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function devProfiles(): { alice: DevProfile; bob: DevProfile; charlie: DevProfile } {
  return {
    alice: {
      profile: "alice",
      token: ALICE_TOKEN,
      accountID: DEV_IDS.aliceAccount,
      petID: DEV_IDS.alicePet,
      accountName: "Alice",
      petName: "奶糖",
      friends: [{
        friendshipID: DEV_IDS.friendship,
        accountID: DEV_IDS.bobAccount,
        petID: DEV_IDS.bobPet,
        accountName: "Bob",
        petName: "团子"
      }]
    },
    bob: {
      profile: "bob",
      token: BOB_TOKEN,
      accountID: DEV_IDS.bobAccount,
      petID: DEV_IDS.bobPet,
      accountName: "Bob",
      petName: "团子",
      friends: [{
        friendshipID: DEV_IDS.friendship,
        accountID: DEV_IDS.aliceAccount,
        petID: DEV_IDS.alicePet,
        accountName: "Alice",
        petName: "奶糖"
      }]
    },
    charlie: {
      profile: "charlie",
      token: CHARLIE_TOKEN,
      accountID: DEV_IDS.charlieAccount,
      petID: DEV_IDS.charliePet,
      accountName: "Charlie",
      petName: "星星",
      friends: []
    }
  };
}
