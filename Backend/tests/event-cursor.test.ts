import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { InMemoryMinoStore } from "../src/memory-store.js";

describe("event cursor tenant isolation", () => {
  it("does not accept another friendship's cursor", async () => {
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const alice = await store.authenticate(profiles.alice.token);
    const friendshipID = profiles.alice.friends[0]!.friendshipID;
    const created = await store.createConversation(alice!, friendshipID, {
      recipientPetID: profiles.bob.petID,
      openingMessage: "cursor source",
      idempotencyKey: randomUUID()
    });
    const cursor = created.events[0]!.id;

    await expect(store.getEvents(alice!, randomUUID(), cursor, 100)).rejects.toMatchObject({
      statusCode: 404,
      code: "not_found"
    });
  });
});
