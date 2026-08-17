import { randomUUID } from "node:crypto";
import { Kysely, PostgresDialect, sql } from "kysely";
import pg from "pg";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { up as migrateInitial } from "../migrations/001_initial.js";
import { up as migrateMVPSafety } from "../migrations/002_mvp_safety.js";
import {
  down as rollbackActiveConversation,
  up as migrateActiveConversation
} from "../migrations/003_one_active_conversation_per_couple.js";
import { up as migrateFriendships } from "../migrations/004_friendships.js";
import { up as migrateModelInferenceSafety } from "../migrations/005_model_inference_safety.js";
import type { AuthContext, DevProfile, PetDecisionResponse } from "../src/domain.js";
import { createDatabase } from "../src/database/connection.js";
import { PostgresMinoStore } from "../src/database/postgres-store.js";
import type { Database } from "../src/database/schema.js";
import { hashToken } from "../src/dev-fixtures.js";
import { LetterCipher } from "../src/security/letter-cipher.js";
import { requestFingerprint } from "../src/security/request-fingerprint.js";

const databaseURL = process.env.DATABASE_URL?.trim();
const postgresTestsEnabled = process.env.RUN_POSTGRES_TESTS === "true" && Boolean(databaseURL);
const describePostgres = postgresTestsEnabled ? describe.sequential : describe.skip;

function createIsolatedDatabase(connectionString: string, schema: string): Kysely<Database> {
  return new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new pg.Pool({
        connectionString,
        max: 10,
        options: `-c search_path=${schema}`
      })
    })
  });
}

describePostgres("PostgresMinoStore integration", () => {
  let schemaName = "";
  let adminDatabase: Kysely<Database> | undefined;
  let database: Kysely<Database> | undefined;
  let store: PostgresMinoStore | undefined;
  let profiles: { alice: DevProfile; bob: DevProfile; charlie: DevProfile };
  let alice: AuthContext;
  let bob: AuthContext;
  let charlie: AuthContext;
  let aliceBobFriendshipID: string;

  beforeEach(async () => {
    schemaName = `mino_integration_${randomUUID().replaceAll("-", "")}`;
    adminDatabase = createDatabase(databaseURL!);
    await adminDatabase.schema.createSchema(schemaName).execute();

    database = createIsolatedDatabase(databaseURL!, schemaName);
    await migrateInitial(database);
    await migrateMVPSafety(database);
    await migrateActiveConversation(database);
    await migrateFriendships(database);
    await migrateModelInferenceSafety(database);

    store = new PostgresMinoStore(database, LetterCipher.development(databaseURL!), true);
    profiles = await store.bootstrapDevProfiles();
    const authenticatedAlice = await store.authenticate(profiles.alice.token);
    const authenticatedBob = await store.authenticate(profiles.bob.token);
    const authenticatedCharlie = await store.authenticate(profiles.charlie.token);
    if (!authenticatedAlice || !authenticatedBob || !authenticatedCharlie) {
      throw new Error("Postgres bootstrap authentication failed");
    }
    alice = authenticatedAlice;
    bob = authenticatedBob;
    charlie = authenticatedCharlie;
    aliceBobFriendshipID = profiles.alice.friends[0]!.friendshipID;
  });

  afterEach(async () => {
    try {
      if (store) {
        await store.close();
      } else if (database) {
        await database.destroy();
      }
    } finally {
      store = undefined;
      database = undefined;
      if (adminDatabase) {
        try {
          if (/^mino_integration_[0-9a-f]{32}$/.test(schemaName)) {
            await adminDatabase.schema.dropSchema(schemaName).ifExists().cascade().execute();
          }
        } finally {
          await adminDatabase.destroy();
          adminDatabase = undefined;
        }
      }
    }
  });

  it("runs migration 004, bootstraps Alice and Bob as friends, and leaves Charlie isolated", async () => {
    expect(alice).toEqual({ accountID: profiles.alice.accountID, petID: profiles.alice.petID });
    expect(bob).toEqual({ accountID: profiles.bob.accountID, petID: profiles.bob.petID });
    expect(charlie).toEqual({ accountID: profiles.charlie.accountID, petID: profiles.charlie.petID });
    await expect(store!.authenticate("not-a-valid-token")).resolves.toBeNull();

    await expect(store!.listFriendships(alice, "accepted")).resolves.toMatchObject([{
      id: aliceBobFriendshipID,
      status: "accepted",
      friend: { accountID: bob.accountID, petID: bob.petID }
    }]);
    await expect(store!.listFriendships(bob, "accepted")).resolves.toMatchObject([{
      id: aliceBobFriendshipID,
      friend: { accountID: alice.accountID, petID: alice.petID }
    }]);
    await expect(store!.listFriendships(charlie)).resolves.toEqual([]);
    await expect(store!.resolveSingleAcceptedFriendship(charlie)).rejects.toMatchObject({
      statusCode: 409,
      code: "friendship_context_required"
    });

    const charliePet = await database!.selectFrom("pets").select("couple_id")
      .where("id", "=", charlie.petID).executeTakeFirstOrThrow();
    expect(charliePet.couple_id).toBeNull();
  });

  it("fails migration 004 explicitly for duplicate legacy pairs and owner pets", async () => {
    await expectLegacyMigrationFailure(adminDatabase!, async (legacy) => {
      const firstAccountID = randomUUID();
      const secondAccountID = randomUUID();
      await legacy.insertInto("accounts").values([
        { id: firstAccountID, display_name: "Pair A", auth_token_hash: hashToken(randomUUID()) },
        { id: secondAccountID, display_name: "Pair B", auth_token_hash: hashToken(randomUUID()) }
      ]).execute();
      await legacy.insertInto("couples").values([
        { id: randomUUID(), account_a_id: firstAccountID, account_b_id: secondAccountID },
        { id: randomUUID(), account_a_id: secondAccountID, account_b_id: firstAccountID }
      ]).execute();
    }, "duplicate legacy relationship pairs must be reconciled before migration 004");

    await expectLegacyMigrationFailure(adminDatabase!, async (legacy) => {
      const ownerAccountID = randomUUID();
      const firstFriendID = randomUUID();
      const secondFriendID = randomUUID();
      const firstScopeID = randomUUID();
      const secondScopeID = randomUUID();
      await legacy.insertInto("accounts").values([
        { id: ownerAccountID, display_name: "Pet owner", auth_token_hash: hashToken(randomUUID()) },
        { id: firstFriendID, display_name: "Friend A", auth_token_hash: hashToken(randomUUID()) },
        { id: secondFriendID, display_name: "Friend B", auth_token_hash: hashToken(randomUUID()) }
      ]).execute();
      await legacy.insertInto("couples").values([
        { id: firstScopeID, account_a_id: ownerAccountID, account_b_id: firstFriendID },
        { id: secondScopeID, account_a_id: ownerAccountID, account_b_id: secondFriendID }
      ]).execute();
      await legacy.insertInto("pets").values([
        { id: randomUUID(), couple_id: firstScopeID, owner_account_id: ownerAccountID, display_name: "Pet A" },
        { id: randomUUID(), couple_id: secondScopeID, owner_account_id: ownerAccountID, display_name: "Pet B" }
      ]).execute();
    }, "duplicate legacy pets per owner must be reconciled before migration 004");
  });

  it("makes friendship request and response idempotent while allowing a rejected pair to retry", async () => {
    const requestKey = randomUUID();
    const requested = await store!.requestFriendship(charlie, {
      addresseeAccountID: alice.accountID,
      idempotencyKey: requestKey
    });
    const replayedRequest = await store!.requestFriendship(charlie, {
      addresseeAccountID: alice.accountID,
      idempotencyKey: requestKey
    });
    expect(replayedRequest.id).toBe(requested.id);
    expect(requested.status).toBe("pending");
    expect(await store!.listFriendships(alice, "pending")).toMatchObject([{ id: requested.id }]);
    await expect(store!.requestFriendship(charlie, {
      addresseeAccountID: bob.accountID,
      idempotencyKey: requestKey
    })).rejects.toMatchObject({ statusCode: 409, code: "idempotency_key_reused" });

    const responseKey = randomUUID();
    const accepted = await store!.respondFriendship(alice, requested.id, {
      response: "accept",
      idempotencyKey: responseKey
    });
    const replayedResponse = await store!.respondFriendship(alice, requested.id, {
      response: "accept",
      idempotencyKey: responseKey
    });
    expect(replayedResponse).toMatchObject({ id: accepted.id, status: "accepted" });
    await expect(store!.respondFriendship(alice, requested.id, {
      response: "reject",
      idempotencyKey: responseKey
    })).rejects.toMatchObject({ statusCode: 409, code: "idempotency_key_reused" });

    const rejectedRequest = await store!.requestFriendship(charlie, {
      addresseeAccountID: bob.accountID,
      idempotencyKey: randomUUID()
    });
    await store!.respondFriendship(bob, rejectedRequest.id, {
      response: "reject",
      idempotencyKey: randomUUID()
    });
    const retried = await store!.requestFriendship(charlie, {
      addresseeAccountID: bob.accountID,
      idempotencyKey: randomUUID()
    });
    expect(retried.status).toBe("pending");
    expect(retried.id).not.toBe(rejectedRequest.id);

    const scope = await database!.selectFrom("friendships").select(["id", "scope_id"])
      .where("id", "=", retried.id).executeTakeFirstOrThrow();
    expect(scope.scope_id).toBe(scope.id);
  });

  it("rejects non-members and cross-friendship resource lookups", async () => {
    const source = await store!.recordLegacyInteraction(alice, aliceBobFriendshipID, {
      senderPetID: alice.petID,
      recipientPetID: bob.petID,
      kind: "wave",
      idempotencyKey: randomUUID()
    });
    await expect(store!.getEvents(charlie, aliceBobFriendshipID, source.events[0]!.id, 100))
      .rejects.toMatchObject({ statusCode: 404, code: "not_found" });

    const aliceCharlie = await createAcceptedFriendship(store!, charlie, alice, alice.accountID);
    const conversation = await store!.createConversation(alice, aliceBobFriendshipID, {
      recipientPetID: bob.petID,
      openingMessage: "scope check",
      idempotencyKey: randomUUID()
    });
    await expect(store!.getConversationMessages(alice, aliceCharlie, conversation.data.conversation.id))
      .rejects.toMatchObject({ statusCode: 404, code: "not_found" });
    await expect(store!.getConversationMessages(charlie, aliceBobFriendshipID, conversation.data.conversation.id))
      .rejects.toMatchObject({ statusCode: 404, code: "not_found" });
  });

  it("reconciles legacy duplicate active conversations before reinstalling the unique index", async () => {
    await rollbackActiveConversation(database!);
    const olderID = randomUUID();
    const newerID = randomUUID();
    await database!.insertInto("conversations").values([
      {
        id: olderID,
        couple_id: aliceBobFriendshipID,
        initiator_pet_id: alice.petID,
        recipient_pet_id: bob.petID,
        status: "active",
        next_speaker_pet_id: bob.petID,
        turn_count: 1,
        created_at: new Date("2026-01-01T00:00:00.000Z"),
        ended_at: null,
        idempotency_key: randomUUID()
      },
      {
        id: newerID,
        couple_id: aliceBobFriendshipID,
        initiator_pet_id: alice.petID,
        recipient_pet_id: bob.petID,
        status: "active",
        next_speaker_pet_id: bob.petID,
        turn_count: 1,
        created_at: new Date("2026-01-02T00:00:00.000Z"),
        ended_at: null,
        idempotency_key: randomUUID()
      }
    ]).execute();

    await migrateActiveConversation(database!);
    const rows = await database!.selectFrom("conversations")
      .select(["id", "status", "next_speaker_pet_id", "ended_at"])
      .where("couple_id", "=", aliceBobFriendshipID)
      .execute();
    expect(rows.find((row) => row.id === olderID)).toMatchObject({ status: "ended", next_speaker_pet_id: null });
    expect(rows.find((row) => row.id === olderID)?.ended_at).not.toBeNull();
    expect(rows.find((row) => row.id === newerID)).toMatchObject({
      status: "active",
      next_speaker_pet_id: bob.petID,
      ended_at: null
    });
  });

  it("serializes idempotent conversation creation and restores the scoped transcript after restart", async () => {
    const replayKey = randomUUID();
    const request = {
      recipientPetID: bob.petID,
      openingMessage: "same request",
      idempotencyKey: replayKey
    };
    const sameRequestResults = await Promise.all([
      store!.createConversation(alice, aliceBobFriendshipID, request),
      store!.createConversation(alice, aliceBobFriendshipID, request)
    ]);
    expect(sameRequestResults[0].data.conversation.id).toBe(sameRequestResults[1].data.conversation.id);
    expect(sameRequestResults.map((result) => result.replayed).sort()).toEqual([false, true]);
    await store!.endConversation(alice, aliceBobFriendshipID, sameRequestResults[0].data.conversation.id, {
      summary: "finished",
      idempotencyKey: randomUUID()
    });

    const conflictKey = randomUUID();
    const differentPayloadResults = await Promise.allSettled([
      store!.createConversation(alice, aliceBobFriendshipID, {
        recipientPetID: bob.petID,
        openingMessage: "payload A",
        idempotencyKey: conflictKey
      }),
      store!.createConversation(alice, aliceBobFriendshipID, {
        recipientPetID: bob.petID,
        openingMessage: "payload B",
        idempotencyKey: conflictKey
      })
    ]);
    expect(differentPayloadResults.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(differentPayloadResults.filter((result) => result.status === "rejected")[0]).toMatchObject({
      reason: { statusCode: 409, code: "idempotency_key_reused" }
    });

    const active = differentPayloadResults.find((result) => result.status === "fulfilled")!.value.data;
    await store!.close();
    store = undefined;
    database = createIsolatedDatabase(databaseURL!, schemaName);
    store = new PostgresMinoStore(database, LetterCipher.development(databaseURL!), true);
    const aliceAfterRestart = await store.authenticate(profiles.alice.token);
    if (!aliceAfterRestart) throw new Error("Alice authentication failed after restart");
    const restored = await store.listConversations(aliceAfterRestart, aliceBobFriendshipID, "active");
    expect(restored.map((conversation) => conversation.id)).toEqual([active.conversation.id]);
    const messages = await store.getConversationMessages(aliceAfterRestart, aliceBobFriendshipID, active.conversation.id);
    expect(messages.map((message) => message.id)).toEqual([active.message.id]);
  });

  it("enforces active visitor and host uniqueness across friendships", async () => {
    const aliceCharlieFriendshipID = await createAcceptedFriendship(store!, charlie, alice, alice.accountID);

    const bobVisitsAlice = await store!.createVisitInvitation(alice, aliceBobFriendshipID, {
      visitorPetID: bob.petID,
      hostAccountID: alice.accountID,
      idempotencyKey: randomUUID()
    });
    const charlieVisitsAlice = await store!.createVisitInvitation(alice, aliceCharlieFriendshipID, {
      visitorPetID: charlie.petID,
      hostAccountID: alice.accountID,
      idempotencyKey: randomUUID()
    });
    const hostResponses = await Promise.allSettled([
      store!.respondVisitInvitation(bob, aliceBobFriendshipID, bobVisitsAlice.data.id, {
        response: "accept",
        idempotencyKey: randomUUID()
      }),
      store!.respondVisitInvitation(charlie, aliceCharlieFriendshipID, charlieVisitsAlice.data.id, {
        response: "accept",
        idempotencyKey: randomUUID()
      })
    ]);
    expect(hostResponses.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(hostResponses.filter((result) => result.status === "rejected")[0]).toMatchObject({
      reason: { statusCode: 409, code: "active_visit_exists" }
    });
    const acceptedHostVisit = hostResponses.find((result) => result.status === "fulfilled")!.value.data;
    await store!.endVisit(alice, acceptedHostVisit.friendshipID, acceptedHostVisit.id, { idempotencyKey: randomUUID() });

    const aliceVisitsBob = await store!.createVisitInvitation(alice, aliceBobFriendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: bob.accountID,
      idempotencyKey: randomUUID()
    });
    const aliceVisitsCharlie = await store!.createVisitInvitation(alice, aliceCharlieFriendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: charlie.accountID,
      idempotencyKey: randomUUID()
    });
    const visitorResponses = await Promise.allSettled([
      store!.respondVisitInvitation(bob, aliceBobFriendshipID, aliceVisitsBob.data.id, {
        response: "accept",
        idempotencyKey: randomUUID()
      }),
      store!.respondVisitInvitation(charlie, aliceCharlieFriendshipID, aliceVisitsCharlie.data.id, {
        response: "accept",
        idempotencyKey: randomUUID()
      })
    ]);
    expect(visitorResponses.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(visitorResponses.filter((result) => result.status === "rejected")[0]).toMatchObject({
      reason: { statusCode: 409, code: "active_visit_exists" }
    });
  });

  it("encrypts letter bodies and enforces friendship plus delivery access", async () => {
    const invitation = await store!.createVisitInvitation(alice, aliceBobFriendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: bob.accountID,
      idempotencyKey: randomUUID()
    });
    await store!.respondVisitInvitation(bob, aliceBobFriendshipID, invitation.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });

    const secretBody = `postgres-secret-${randomUUID()}`;
    const idempotencyKey = randomUUID();
    const created = await store!.createVisitLetter(bob, aliceBobFriendshipID, invitation.data.id, {
      body: secretBody,
      idempotencyKey
    });
    expect(created.data.body).toBe(secretBody);
    const storedLetter = await database!.selectFrom("letters").select("body")
      .where("id", "=", created.data.id).executeTakeFirstOrThrow();
    expect(storedLetter.body).not.toContain(secretBody);
    const storedIdempotency = await database!.selectFrom("idempotency_records").select(["response", "request_fingerprint"])
      .where("couple_id", "=", aliceBobFriendshipID)
      .where("scope", "=", "visit-letter")
      .where("idempotency_key", "=", idempotencyKey)
      .executeTakeFirstOrThrow();
    expect(JSON.stringify(storedIdempotency.response)).not.toContain(secretBody);
    expect(storedIdempotency.request_fingerprint).toMatch(/^hmac-sha256:[0-9a-f]{64}$/);
    expect(storedIdempotency.request_fingerprint).not.toBe(requestFingerprint({
      visitID: invitation.data.id,
      body: secretBody,
      idempotencyKey
    }));

    await expect(store!.getLetter(alice, aliceBobFriendshipID, created.data.id))
      .rejects.toMatchObject({ statusCode: 404, code: "not_found" });
    await expect(store!.getLetter(charlie, aliceBobFriendshipID, created.data.id))
      .rejects.toMatchObject({ statusCode: 404, code: "not_found" });
    await store!.endVisit(bob, aliceBobFriendshipID, invitation.data.id, { idempotencyKey: randomUUID() });
    await expect(store!.getLetter(alice, aliceBobFriendshipID, created.data.id))
      .resolves.toMatchObject({ body: secretBody, status: "delivered" });
  });

  it("continues event catch-up from a friendship cursor after restart", async () => {
    const first = await store!.recordLegacyInteraction(alice, aliceBobFriendshipID, {
      senderPetID: alice.petID,
      recipientPetID: bob.petID,
      kind: "wave",
      idempotencyKey: randomUUID()
    });
    const second = await store!.recordLegacyInteraction(alice, aliceBobFriendshipID, {
      senderPetID: alice.petID,
      recipientPetID: bob.petID,
      kind: "play",
      idempotencyKey: randomUUID()
    });
    const firstPage = await store!.getEvents(alice, aliceBobFriendshipID, undefined, 1);
    expect(firstPage.events.map((event) => event.id)).toEqual([first.events[0]!.id]);

    await store!.close();
    store = undefined;
    database = createIsolatedDatabase(databaseURL!, schemaName);
    store = new PostgresMinoStore(database, LetterCipher.development(databaseURL!), true);
    const aliceAfterRestart = await store.authenticate(profiles.alice.token);
    if (!aliceAfterRestart) throw new Error("Alice authentication failed after restart");
    const catchUp = await store.getEvents(aliceAfterRestart, aliceBobFriendshipID, firstPage.nextCursor!, 100);
    expect(catchUp.events.map((event) => event.id)).toEqual([second.events[0]!.id]);
    const empty = await store.getEvents(aliceAfterRestart, aliceBobFriendshipID, catchUp.nextCursor!, 100);
    expect(empty.events).toEqual([]);
    expect(empty.nextCursor).toBe(catchUp.nextCursor);
  });

  it("serializes friendship event commits before advancing the durable cursor", async () => {
    await sql`
      CREATE FUNCTION delay_slow_friendship_event() RETURNS trigger AS $$
      BEGIN
        IF NEW.payload ->> 'kind' = 'cursor_slow' THEN
          PERFORM pg_advisory_xact_lock(hashtext(TG_TABLE_SCHEMA || ':slow-event-marker'));
          PERFORM pg_sleep(0.5);
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql
    `.execute(database!);
    await sql`
      CREATE TRIGGER delay_slow_friendship_event
      AFTER INSERT ON couple_events
      FOR EACH ROW EXECUTE FUNCTION delay_slow_friendship_event()
    `.execute(database!);

    const slow = store!.recordLegacyInteraction(alice, aliceBobFriendshipID, {
      senderPetID: alice.petID,
      recipientPetID: bob.petID,
      kind: "cursor_slow",
      idempotencyKey: randomUUID()
    });
    await waitForAdvisoryLock(database!, `${schemaName}:slow-event-marker`);

    let fastCompleted = false;
    const fast = store!.recordLegacyInteraction(alice, aliceBobFriendshipID, {
      senderPetID: alice.petID,
      recipientPetID: bob.petID,
      kind: "cursor_fast",
      idempotencyKey: randomUUID()
    }).then((result) => {
      fastCompleted = true;
      return result;
    });
    await new Promise((resolve) => setTimeout(resolve, 75));
    expect(fastCompleted).toBe(false);

    const [slowResult, fastResult] = await Promise.all([slow, fast]);
    expect(slowResult.events[0]!.sequence).toBeLessThan(fastResult.events[0]!.sequence);
    const page = await store!.getEvents(alice, aliceBobFriendshipID, slowResult.events[0]!.id, 100);
    expect(page.events.map((event) => event.id)).toContain(fastResult.events[0]!.id);
  });

  it("redacts a pet's active visit when presence is read through another friendship", async () => {
    const aliceCharlieFriendshipID = await createAcceptedFriendship(
      store!,
      charlie,
      alice,
      alice.accountID
    );
    const invitation = await store!.createVisitInvitation(alice, aliceCharlieFriendshipID, {
      visitorPetID: alice.petID,
      hostAccountID: charlie.accountID,
      idempotencyKey: randomUUID()
    });
    await store!.respondVisitInvitation(charlie, aliceCharlieFriendshipID, invitation.data.id, {
      response: "accept",
      idempotencyKey: randomUUID()
    });

    const unrelatedPresence = await store!.getPresence(alice, aliceBobFriendshipID);
    expect(unrelatedPresence.activeVisits).toEqual([]);
    expect(unrelatedPresence.pets.find((pet) => pet.petID === alice.petID)).toMatchObject({
      phase: "visiting",
      currentHostAccountID: null,
      activeVisitID: null
    });
    expect(JSON.stringify(unrelatedPresence)).not.toContain(charlie.accountID);
    expect(JSON.stringify(unrelatedPresence)).not.toContain(invitation.data.id);

    const owningPresence = await store!.getPresence(alice, aliceCharlieFriendshipID);
    expect(owningPresence.activeVisits.map((visit) => visit.id)).toEqual([invitation.data.id]);
    expect(owningPresence.pets.find((pet) => pet.petID === alice.petID)).toMatchObject({
      phase: "visiting",
      currentHostAccountID: charlie.accountID,
      activeVisitID: invitation.data.id
    });
  });

  it("scopes model inference replay and usage to accounts without retrying uncertain calls", async () => {
    const inferenceID = randomUUID();
    const fingerprint = store!.fingerprintRequest({ inferenceID, purpose: "account-scope-test" });
    const response: PetDecisionResponse = {
      inferenceID,
      decision: { kind: "speak_to_owner", text: "hello" },
      memoryDisposition: { kind: "session" },
      replayed: false,
      usage: { inputTokens: 23, outputTokens: 7 }
    };
    await expect(store!.claimModelInference(alice, inferenceID, "mock", "v1", fingerprint)).resolves.toEqual({ state: "claimed" });
    await expect(store!.claimModelInference(bob, inferenceID, "mock", "v1", fingerprint)).resolves.toEqual({ state: "claimed" });
    await expect(store!.claimModelInference(charlie, inferenceID, "mock", "v1", fingerprint)).resolves.toEqual({ state: "claimed" });
    await store!.completeModelInference(alice, inferenceID, "completed", 23, 7, response);
    await expect(store!.claimModelInference(bob, inferenceID, "mock", "v1", fingerprint)).resolves.toEqual({ state: "in_progress" });
    const rows = await database!.selectFrom("model_usage").select(["account_id", "couple_id"])
      .where("inference_id", "=", inferenceID).execute();
    expect(rows.map((row) => row.account_id).sort()).toEqual([
      alice.accountID,
      bob.accountID,
      charlie.accountID
    ].sort());
    expect(rows.every((row) => row.couple_id === null)).toBe(true);

    await store!.close();
    store = undefined;
    database = createIsolatedDatabase(databaseURL!, schemaName);
    store = new PostgresMinoStore(database, LetterCipher.development(databaseURL!), true);
    const aliceAfterRestart = await store.authenticate(profiles.alice.token);
    const bobAfterRestart = await store.authenticate(profiles.bob.token);
    if (!aliceAfterRestart || !bobAfterRestart) throw new Error("Authentication failed after restart");
    await expect(store.claimModelInference(aliceAfterRestart, inferenceID, "mock", "v1", fingerprint))
      .resolves.toEqual({ state: "replay", response: { ...response, replayed: true } });
    await expect(store.claimModelInference(bobAfterRestart, inferenceID, "mock", "v1", fingerprint))
      .resolves.toEqual({ state: "in_progress" });

    const staleInferenceID = randomUUID();
    const staleFingerprint = store.fingerprintRequest({ inferenceID: staleInferenceID });
    await expect(store.claimModelInference(aliceAfterRestart, staleInferenceID, "mock", "v1", staleFingerprint, 60_000))
      .resolves.toEqual({ state: "claimed" });
    await database.updateTable("model_usage").set({ claimed_at: new Date(Date.now() - 60_001) })
      .where("account_id", "=", aliceAfterRestart.accountID)
      .where("inference_id", "=", staleInferenceID).execute();
    await expect(store.claimModelInference(aliceAfterRestart, staleInferenceID, "mock", "v1", staleFingerprint, 60_000))
      .resolves.toEqual({ state: "outcome_unknown" });
  });

  it("keeps pets when a legacy scope is deleted", async () => {
    const accountID = randomUUID();
    const partnerID = randomUUID();
    const scopeID = randomUUID();
    const petID = randomUUID();
    await database!.insertInto("accounts").values([
      { id: accountID, display_name: "Scope owner", auth_token_hash: hashToken(randomUUID()) },
      { id: partnerID, display_name: "Scope partner", auth_token_hash: hashToken(randomUUID()) }
    ]).execute();
    await database!.insertInto("couples").values({
      id: scopeID,
      account_a_id: accountID,
      account_b_id: partnerID
    }).execute();
    await database!.insertInto("pets").values({
      id: petID,
      couple_id: scopeID,
      owner_account_id: accountID,
      display_name: "Persistent pet"
    }).execute();
    await database!.deleteFrom("couples").where("id", "=", scopeID).execute();
    await expect(database!.selectFrom("pets").select("couple_id").where("id", "=", petID).executeTakeFirst())
      .resolves.toMatchObject({ couple_id: null });
  });
});

async function createAcceptedFriendship(
  store: PostgresMinoStore,
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

async function waitForAdvisoryLock(database: Kysely<Database>, key: string): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const isHeld = await database.connection().execute(async (connection) => {
      const result = await sql<{ acquired: boolean }>`
        select pg_try_advisory_lock(hashtext(${key})) as acquired
      `.execute(connection);
      const acquired = result.rows[0]?.acquired ?? false;
      if (acquired) {
        await sql`select pg_advisory_unlock(hashtext(${key}))`.execute(connection);
      }
      return !acquired;
    });
    if (isHeld) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out waiting for the slow event transaction");
}

async function expectLegacyMigrationFailure(
  adminDatabase: Kysely<Database>,
  seed: (database: Kysely<Database>) => Promise<void>,
  expectedMessage: string
): Promise<void> {
  const legacySchema = `mino_legacy_${randomUUID().replaceAll("-", "")}`;
  await adminDatabase.schema.createSchema(legacySchema).execute();
  const legacyDatabase = createIsolatedDatabase(databaseURL!, legacySchema);
  try {
    await migrateInitial(legacyDatabase);
    await migrateMVPSafety(legacyDatabase);
    await migrateActiveConversation(legacyDatabase);
    await seed(legacyDatabase);
    await expect(migrateFriendships(legacyDatabase)).rejects.toThrow(expectedMessage);
  } finally {
    await legacyDatabase.destroy();
    if (/^mino_legacy_[0-9a-f]{32}$/.test(legacySchema)) {
      await adminDatabase.schema.dropSchema(legacySchema).ifExists().cascade().execute();
    }
  }
}
