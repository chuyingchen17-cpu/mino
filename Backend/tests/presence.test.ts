import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import type { AuthContext, DevProfile } from "../src/domain.js";
import { InMemoryMinoStore } from "../src/memory-store.js";

describe("global pet presence privacy", () => {
  it("reports a pet as away without exposing another friendship's visit routing", async () => {
    const { store, profiles, alice, charlie } = await context();
    const aliceCharlieFriendshipID = await acceptFriendship(
      store,
      charlie,
      alice,
      alice.accountID
    );
    const invitation = await store.createVisitInvitation(alice, aliceCharlieFriendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: charlie.accountID,
      idempotencyKey: randomUUID()
    });
    await store.respondVisitInvitation(charlie, aliceCharlieFriendshipID, invitation.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });

    const aliceBobFriendshipID = profiles.alice.friends[0]!.friendshipID;
    const unrelatedPresence = await store.getPresence(alice, aliceBobFriendshipID);
    expect(unrelatedPresence.activeVisits).toEqual([]);
    expect(unrelatedPresence.pets.find((pet) => pet.petID === alice.petID)).toMatchObject({
      phase: "visiting",
      currentHostAccountID: null,
      activeVisitID: null
    });
    expect(JSON.stringify(unrelatedPresence)).not.toContain(charlie.accountID);
    expect(JSON.stringify(unrelatedPresence)).not.toContain(invitation.data.id);

    const owningPresence = await store.getPresence(alice, aliceCharlieFriendshipID);
    expect(owningPresence.activeVisits.map((visit) => visit.id)).toEqual([invitation.data.id]);
    expect(owningPresence.pets.find((pet) => pet.petID === alice.petID)).toMatchObject({
      phase: "visiting",
      currentHostAccountID: charlie.accountID,
      activeVisitID: invitation.data.id
    });
  });

  it("returns both active visits when the two pets visit each other simultaneously", async () => {
    const { store, profiles, alice, bob } = await context();
    const friendshipID = profiles.alice.friends[0]!.friendshipID;
    const aliceVisit = await store.createVisitInvitation(alice, friendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: bob.accountID,
      idempotencyKey: randomUUID()
    });
    await store.respondVisitInvitation(bob, friendshipID, aliceVisit.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });
    const bobVisit = await store.createVisitInvitation(alice, friendshipID, {
      visitorPetID: bob.petID,
      hostAccountID: alice.accountID,
      idempotencyKey: randomUUID()
    });
    await store.respondVisitInvitation(bob, friendshipID, bobVisit.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });

    const presence = await store.getPresence(alice, friendshipID);
    expect(presence.activeVisits.map((visit) => visit.id).sort()).toEqual([
      aliceVisit.data.id,
      bobVisit.data.id
    ].sort());
    expect(presence.pets).toEqual(expect.arrayContaining([
      expect.objectContaining({
        petID: alice.petID,
        phase: "visiting",
        currentHostAccountID: bob.accountID,
        activeVisitID: aliceVisit.data.id
      }),
      expect.objectContaining({
        petID: bob.petID,
        phase: "visiting",
        currentHostAccountID: alice.accountID,
        activeVisitID: bobVisit.data.id
      })
    ]));
  });
});

async function context(): Promise<{
  store: InMemoryMinoStore;
  profiles: { alice: DevProfile; bob: DevProfile; charlie: DevProfile };
  alice: AuthContext;
  bob: AuthContext;
  charlie: AuthContext;
}> {
  const store = new InMemoryMinoStore();
  const profiles = await store.bootstrapDevProfiles();
  const alice = await store.authenticate(profiles.alice.token);
  const bob = await store.authenticate(profiles.bob.token);
  const charlie = await store.authenticate(profiles.charlie.token);
  if (!alice || !bob || !charlie) throw new Error("Development profiles failed to authenticate");
  return { store, profiles, alice, bob, charlie };
}

async function acceptFriendship(
  store: InMemoryMinoStore,
  requester: AuthContext,
  addressee: AuthContext,
  addresseeAccountID: string
): Promise<string> {
  const pending = await store.requestFriendship(requester, {
    addresseeAccountID,
    idempotencyKey: randomUUID()
  });
  const accepted = await store.respondFriendship(addressee, pending.id, {
    response: "accept",
    idempotencyKey: randomUUID()
  });
  return accepted.id;
}
