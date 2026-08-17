import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import type { AuthContext } from "../src/domain.js";
import { InMemoryMinoStore } from "../src/memory-store.js";

describe("letter access isolation", () => {
  it("hides a letter from its recipient until delivery and from every non-party context", async () => {
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const alice = await store.authenticate(profiles.alice.token);
    const bob = await store.authenticate(profiles.bob.token);
    expect(alice).not.toBeNull();
    expect(bob).not.toBeNull();
    const friendshipID = profiles.alice.friends[0]!.friendshipID;

    const invitation = await store.createVisitInvitation(alice!, friendshipID, {
      visitorPetID: alice!.petID,
      hostAccountID: bob!.accountID,
      idempotencyKey: randomUUID()
    });
    await store.respondVisitInvitation(bob!, friendshipID, invitation.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });
    const letter = await store.createVisitLetter(bob!, friendshipID, invitation.data.id, {
      body: "只允许真正的收件人阅读",
      idempotencyKey: randomUUID()
    });

    await expect(store.getLetter(alice!, friendshipID, letter.data.id)).rejects.toMatchObject({ statusCode: 404 });
    await expect(store.getLetter(bob!, friendshipID, letter.data.id)).resolves.toMatchObject({ body: letter.data.body });

    const foreignTenant: AuthContext = { ...alice!, accountID: randomUUID() };
    await expect(store.getLetter(foreignTenant, friendshipID, letter.data.id)).rejects.toMatchObject({ statusCode: 404 });
    const nonParty: AuthContext = { ...alice!, accountID: randomUUID() };
    await expect(store.getLetter(nonParty, friendshipID, letter.data.id)).rejects.toMatchObject({ statusCode: 404 });

    await store.endVisit(alice!, friendshipID, invitation.data.id, { idempotencyKey: randomUUID() });
    await expect(store.getLetter(alice!, friendshipID, letter.data.id)).resolves.toMatchObject({
      body: letter.data.body,
      status: "delivered"
    });
  });
});
