import type { AuthContext } from "../domain/models";
import {
  careFromRow,
  clamped,
  familiarityTier,
  publicCare,
  type PetCareEffect,
  type PetCareInteractionKind,
  type PetCareRow,
  type PetCareState,
  type PetFamiliarity,
  type PetInteractionOutcome,
  type PetInteractionReceipt,
  type VisitInteractionSummary
} from "../domain/pet-care";
import { conflict, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement
} from "../storage/events-repository";
import { executeIdempotent } from "./idempotency";

interface TargetAccess {
  relationship: "owner" | "friend";
  friendshipID: string | null;
  visitID: string | null;
  ownerAccountID: string;
}

interface FamiliarityRow {
  pet_id: string;
  friendship_id: string;
  score: number;
  version: number;
  updated_at_ms: number;
}

interface RecentGainRow {
  gained: number;
}

const zeroEffect: PetCareEffect = { fullness: 0, energy: 0, mood: 0, bond: 0, familiarity: 0 };

function dayStart(now: number): number {
  const value = new Date(now);
  return Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate());
}

async function ensureCareRow(db: D1Database, petID: string, now: number): Promise<PetCareRow> {
  await db.prepare(`
    INSERT OR IGNORE INTO pet_care_states(pet_id, evaluated_at_ms, updated_at_ms)
    SELECT id, ?, ? FROM pets WHERE id = ?
  `).bind(now, now, petID).run();
  const row = await db.prepare("SELECT * FROM pet_care_states WHERE pet_id = ?")
    .bind(petID).first<PetCareRow>();
  if (!row) throw notFound("pet");
  return row;
}

async function targetAccess(
  db: D1Database,
  context: AuthContext,
  petID: string,
  visitID?: string
): Promise<TargetAccess> {
  if (petID === context.petID && !visitID) {
    return { relationship: "owner", friendshipID: null, visitID: null, ownerAccountID: context.accountID };
  }
  if (!visitID) throw notFound("pet interaction");
  const visit = await db.prepare(`
    SELECT visitor_owner_account_id, host_account_id, visitor_pet_id, friendship_id
    FROM visits WHERE id = ? AND status = 'active'
  `).bind(visitID).first<{
    visitor_owner_account_id: string;
    host_account_id: string;
    visitor_pet_id: string;
    friendship_id: string;
  }>();
  if (!visit || visit.host_account_id !== context.accountID || visit.visitor_pet_id !== petID) {
    throw notFound("pet interaction");
  }
  return {
    relationship: "friend",
    friendshipID: visit.friendship_id,
    visitID,
    ownerAccountID: visit.visitor_owner_account_id
  };
}

function transition(
  state: PetCareState,
  kind: PetCareInteractionKind,
  relationship: "owner" | "friend",
  repeated: boolean,
  restOnCooldown: boolean,
  relationshipGainRemaining: number
): { state: PetCareState; outcome: PetInteractionOutcome; effect: PetCareEffect } {
  if (repeated) return { state, outcome: "cosmetic_only", effect: zeroEffect };
  let outcome: PetInteractionOutcome = "applied";
  let base: PetCareEffect = zeroEffect;
  switch (kind) {
    case "pet": base = { fullness: 0, energy: 0, mood: 4, bond: 1, familiarity: 1 }; break;
    case "feed":
      if (state.fullness >= 90) outcome = "too_full";
      else base = { fullness: 20, energy: 0, mood: 3, bond: 1, familiarity: 1 };
      break;
    case "play":
      if (state.energy < 15) outcome = "too_tired";
      else base = { fullness: 0, energy: -12, mood: 14, bond: 2, familiarity: 2 };
      break;
    case "walk":
      if (state.energy < 25) outcome = "too_tired";
      else base = { fullness: 0, energy: -18, mood: 12, bond: 2, familiarity: 2 };
      break;
    case "rest":
      if (relationship !== "owner") outcome = "cosmetic_only";
      else if (restOnCooldown) outcome = "resting_cooldown";
      else base = { fullness: 0, energy: 15, mood: 0, bond: 0, familiarity: 0 };
      break;
    case "cuddle": base = { fullness: 0, energy: 0, mood: 6, bond: 2, familiarity: 2 }; break;
    case "flower": base = { fullness: 0, energy: 0, mood: 5, bond: 1, familiarity: 1 }; break;
  }
  const relationshipGain = Math.min(
    Math.max(0, relationshipGainRemaining),
    relationship === "owner" ? base.bond : base.familiarity
  );
  const effect: PetCareEffect = {
    fullness: base.fullness,
    energy: base.energy,
    mood: base.mood,
    bond: relationship === "owner" ? relationshipGain : 0,
    familiarity: relationship === "friend" ? relationshipGain : 0
  };
  return {
    outcome,
    effect,
    state: {
      fullness: clamped(state.fullness + effect.fullness),
      energy: clamped(state.energy + effect.energy),
      mood: clamped(state.mood + effect.mood),
      bond: clamped(state.bond + effect.bond),
      version: state.version + 1,
      evaluatedAt: state.evaluatedAt
    }
  };
}

function familiarityFromRow(row: FamiliarityRow): PetFamiliarity {
  return {
    petID: row.pet_id,
    friendshipID: row.friendship_id,
    score: row.score,
    tier: familiarityTier(row.score),
    version: row.version,
    updatedAt: row.updated_at_ms
  };
}

export async function getOwnPetCare(db: D1Database, context: AuthContext, now = Date.now()) {
  return careFromRow(await ensureCareRow(db, context.petID, now), now);
}

export async function interactWithPet(
  db: D1Database,
  context: AuthContext,
  petID: string,
  input: { kind: PetCareInteractionKind; visitID?: string; occurredAt: number },
  idempotencyKey: string,
  now = Date.now()
) {
  if (input.occurredAt > now + 5 * 60_000 || input.occurredAt < now - 7 * 86_400_000) {
    throw conflict("interaction_time_invalid", "Interaction time is outside the accepted window");
  }
  const access = await targetAccess(db, context, petID, input.visitID);
  if (input.kind === "rest" && access.relationship !== "owner") {
    throw notFound("pet interaction");
  }
  return executeIdempotent<PetInteractionReceipt>(
    db,
    context,
    `interactPet:${petID}`,
    idempotencyKey,
    input,
    async (fingerprint) => {
      const careRow = await ensureCareRow(db, petID, now);
      const state = careFromRow(careRow, now);
      const recent = await db.prepare(`
        SELECT id FROM pet_interactions
        WHERE target_pet_id = ? AND actor_account_id = ? AND kind = ? AND created_at_ms >= ?
        LIMIT 1
      `).bind(petID, context.accountID, input.kind, now - 30_000).first();
      const restRecent = input.kind === "rest"
        ? await db.prepare(`
            SELECT id FROM pet_interactions
            WHERE target_pet_id = ? AND actor_account_id = ? AND kind = 'rest'
              AND outcome = 'applied' AND created_at_ms >= ? LIMIT 1
          `).bind(petID, context.accountID, now - 3_600_000).first()
        : null;
      const gainColumn = access.relationship === "owner" ? "bond_delta" : "familiarity_delta";
      const gainWhere = access.relationship === "owner"
        ? "target_pet_id = ? AND actor_account_id = ?"
        : "target_pet_id = ? AND friendship_id = ?";
      const gained = await db.prepare(`
        SELECT COALESCE(SUM(${gainColumn}), 0) AS gained FROM pet_interactions
        WHERE ${gainWhere} AND created_at_ms >= ?
      `).bind(
        petID,
        access.relationship === "owner" ? context.accountID : access.friendshipID,
        dayStart(now)
      ).first<RecentGainRow>();
      const limit = access.relationship === "owner" ? 8 : 10;
      const result = transition(
        state,
        input.kind,
        access.relationship,
        Boolean(recent),
        Boolean(restRecent),
        limit - (gained?.gained ?? 0)
      );

      let familiarity: PetFamiliarity | null = null;
      let familiarityRow: FamiliarityRow | null = null;
      if (access.friendshipID) {
        familiarityRow = await db.prepare(`
          SELECT * FROM pet_familiarities WHERE pet_id = ? AND friendship_id = ?
        `).bind(petID, access.friendshipID).first<FamiliarityRow>();
        const score = clamped((familiarityRow?.score ?? 0) + result.effect.familiarity);
        familiarity = {
          petID,
          friendshipID: access.friendshipID,
          score,
          tier: familiarityTier(score),
          version: (familiarityRow?.version ?? 0) + 1,
          updatedAt: now
        };
      }
      const interactionID = idempotencyKey;
      const receipt: PetInteractionReceipt = {
        id: interactionID,
        targetPetID: petID,
        actorAccountID: context.accountID,
        friendshipID: access.friendshipID,
        visitID: access.visitID,
        kind: input.kind,
        outcome: result.outcome,
        effect: result.effect,
        careState: access.relationship === "owner" ? result.state : null,
        publicCare: publicCare(result.state),
        familiarity,
        occurredAt: input.occurredAt
      };
      const recipients = [...new Set([context.accountID, access.ownerAccountID])];
      const eventStatements = recipients.map((recipientAccountID) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID: access.friendshipID,
        type: "pet.care.updated",
        aggregateType: "pet_care",
        aggregateID: petID,
        aggregateVersion: result.state.version,
        payload: {
          petID,
          publicCare: receipt.publicCare,
          ...(recipientAccountID === access.ownerAccountID ? { careState: result.state } : {}),
          ...(familiarity ? { familiarity } : {})
        },
        timelineVisible: false,
        occurredAt: now
      }, "pet_interactions", "id", interactionID, interactionID));
      const statements: D1PreparedStatement[] = [
        db.prepare(`
          UPDATE pet_care_states SET fullness = ?, energy = ?, mood = ?, bond = ?,
            version = ?, last_transition_id = ?, evaluated_at_ms = ?, updated_at_ms = ?
          WHERE pet_id = ? AND version = ?
        `).bind(
          result.state.fullness, result.state.energy, result.state.mood, result.state.bond,
          result.state.version, interactionID, now, now, petID, careRow.version
        ),
        db.prepare(`
          INSERT INTO pet_interactions(
            id, target_pet_id, actor_account_id, friendship_id, visit_id, kind, outcome,
            fullness_delta, energy_delta, mood_delta, bond_delta, familiarity_delta,
            occurred_at_ms, created_at_ms
          )
          SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
          FROM pet_care_states WHERE pet_id = ? AND last_transition_id = ?
        `).bind(
          interactionID, petID, context.accountID, access.friendshipID, access.visitID,
          input.kind, result.outcome, result.effect.fullness, result.effect.energy,
          result.effect.mood, result.effect.bond, result.effect.familiarity,
          input.occurredAt, now, petID, interactionID
        )
      ];
      if (familiarity && access.friendshipID) {
        statements.push(db.prepare(`
          INSERT INTO pet_familiarities(pet_id, friendship_id, score, version, updated_at_ms)
          SELECT ?, ?, ?, ?, ? FROM pet_interactions WHERE id = ?
          ON CONFLICT(pet_id, friendship_id) DO UPDATE SET
            score = excluded.score, version = excluded.version, updated_at_ms = excluded.updated_at_ms
        `).bind(petID, access.friendshipID, familiarity.score, familiarity.version, now, interactionID));
      }
      if (access.visitID && ["applied", "cosmetic_only"].includes(result.outcome)) {
        const column = `${input.kind}_count`;
        statements.push(db.prepare(`
          INSERT INTO visit_interaction_stats(visit_id, ${column}, familiarity_gained, updated_at_ms)
          SELECT ?, 1, ?, ? FROM pet_interactions WHERE id = ?
          ON CONFLICT(visit_id) DO UPDATE SET
            ${column} = ${column} + 1,
            familiarity_gained = familiarity_gained + excluded.familiarity_gained,
            updated_at_ms = excluded.updated_at_ms
        `).bind(access.visitID, result.effect.familiarity, now, interactionID));
      }
      statements.push(...eventStatements);
      statements.push(idempotencyFromMarkerStatement(
        db, context.accountID, `interactPet:${petID}`, idempotencyKey, fingerprint,
        201, receipt, now, "pet_interactions", "id", interactionID, interactionID
      ));
      return { data: receipt, status: 201, notifyAccountIDs: recipients, statements };
    },
    4
  );
}

export async function visitInteractionSummary(
  db: D1Database,
  visitID: string,
  letterAttached: boolean
): Promise<VisitInteractionSummary> {
  const row = await db.prepare("SELECT * FROM visit_interaction_stats WHERE visit_id = ?")
    .bind(visitID).first<Record<string, number>>();
  const counts: Partial<Record<PetCareInteractionKind, number>> = {};
  for (const kind of ["pet", "feed", "play", "walk", "rest", "cuddle", "flower"] as const) {
    const count = row?.[`${kind}_count`] ?? 0;
    if (count > 0) counts[kind] = count;
  }
  return {
    counts,
    familiarityGained: row?.familiarity_gained ?? 0,
    letterAttached
  };
}
