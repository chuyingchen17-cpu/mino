import type { AuthContext, PublicPetSnapshot } from "../domain/models";
import { badRequest, conflict, isUniqueConstraintError, notFound } from "../errors";
import {
  accountEventFromMarkerStatement,
  idempotencyFromMarkerStatement,
  idempotencyStatement
} from "../storage/events-repository";
import { publicPetSnapshot } from "../storage/visits-repository";
import { executeIdempotent } from "./idempotency";

export const PET_APPEARANCE_SCHEMA_VERSION = 1 as const;
export const PET_APPEARANCE_CATALOG_VERSION = 2 as const;
export const PET_CHARACTER_RIG_ID = "maltese-pair-v1" as const;
export const PET_CHARACTER_BODIES = ["maltese-white", "retriever-yellow"] as const;

export type PetCharacterBody = typeof PET_CHARACTER_BODIES[number];

export interface PetAppearanceSelectionCommand {
  appearanceSchemaVersion: typeof PET_APPEARANCE_SCHEMA_VERSION;
  appearanceCatalogVersion: typeof PET_APPEARANCE_CATALOG_VERSION;
  appearance: {
    rigID: typeof PET_CHARACTER_RIG_ID;
    body: PetCharacterBody;
  };
}

interface PetAppearanceRow {
  appearance_schema_version: number;
  appearance_catalog_version: number;
  appearance_json: string;
  appearance_version: number;
}

function parseAppearance(value: string): Record<string, unknown> {
  const parsed: unknown = JSON.parse(value);
  return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)
    ? parsed as Record<string, unknown>
    : {};
}

function selectedCharacter(row: PetAppearanceRow): PetCharacterBody | null {
  const appearance = parseAppearance(row.appearance_json);
  if (row.appearance_schema_version !== PET_APPEARANCE_SCHEMA_VERSION ||
      row.appearance_catalog_version !== PET_APPEARANCE_CATALOG_VERSION ||
      appearance.rigID !== PET_CHARACTER_RIG_ID) {
    return null;
  }
  return PET_CHARACTER_BODIES.find((body) => body === appearance.body) ?? null;
}

function isSelectableLegacyAppearance(row: PetAppearanceRow): boolean {
  const appearance = parseAppearance(row.appearance_json);
  return Object.keys(appearance).length === 0 || appearance.rigID === "mino-default";
}

function validateSelection(input: PetAppearanceSelectionCommand): void {
  if (input.appearanceSchemaVersion !== PET_APPEARANCE_SCHEMA_VERSION ||
      input.appearanceCatalogVersion !== PET_APPEARANCE_CATALOG_VERSION ||
      input.appearance.rigID !== PET_CHARACTER_RIG_ID ||
      !PET_CHARACTER_BODIES.includes(input.appearance.body)) {
    throw badRequest(
      "unsupported_pet_appearance",
      "Choose one of the supported Mino pet characters"
    );
  }
}

export async function updatePetAppearance(
  db: D1Database,
  context: AuthContext,
  input: PetAppearanceSelectionCommand,
  idempotencyKey: string,
  now = Date.now()
) {
  validateSelection(input);
  const execute = () => executeIdempotent<PublicPetSnapshot>(
    db, context, "updatePetAppearance", idempotencyKey, input,
    async (fingerprint) => {
      const pet = await db.prepare(`
        SELECT appearance_schema_version, appearance_catalog_version,
          appearance_json, appearance_version
        FROM pets WHERE id = ? AND owner_account_id = ?
      `).bind(context.petID, context.accountID).first<PetAppearanceRow>();
      if (!pet) throw notFound("pet");
      const currentCharacter = selectedCharacter(pet);
      if (currentCharacter !== null) {
        if (currentCharacter !== input.appearance.body) {
          throw conflict(
            "appearance_locked",
            "This pet character was already selected and cannot be changed"
          );
        }
        const data = await publicPetSnapshot(db, context.petID);
        return {
          data,
          status: 200,
          notifyAccountIDs: [],
          statements: [idempotencyFromMarkerStatement(
            db, context.accountID, "updatePetAppearance", idempotencyKey,
            fingerprint, 200, data, now, "pets", "appearance_version",
            context.petID, pet.appearance_version
          )]
        };
      }
      if (!isSelectableLegacyAppearance(pet)) {
        throw conflict(
          "appearance_locked",
          "This pet already has an appearance that cannot be replaced by character selection"
        );
      }
      const version = pet.appearance_version + 1;
      const activeVisit = await db.prepare(`
        SELECT id, friendship_id, host_account_id FROM visits
        WHERE visitor_pet_id = ? AND status = 'active'
      `).bind(context.petID).first<{ id: string; friendship_id: string; host_account_id: string }>();
      const friends = await db.prepare(`
        SELECT id AS friendship_id,
          CASE WHEN requester_account_id = ? THEN addressee_account_id
               ELSE requester_account_id END AS account_id
        FROM friendships
        WHERE status = 'accepted'
          AND ? IN (requester_account_id, addressee_account_id)
      `).bind(context.accountID, context.accountID).all<{
        friendship_id: string;
        account_id: string;
      }>();
      const appearance = {
        rigID: PET_CHARACTER_RIG_ID,
        body: input.appearance.body
      };
      const data: PublicPetSnapshot = {
        petID: context.petID,
        displayName: (await publicPetSnapshot(db, context.petID)).displayName,
        appearanceSchemaVersion: input.appearanceSchemaVersion,
        appearanceCatalogVersion: input.appearanceCatalogVersion,
        appearanceVersion: version,
        appearance
      };
      const recipientFriendships = new Map<string, string | null>([[context.accountID, null]]);
      for (const friend of friends.results) {
        recipientFriendships.set(friend.account_id, friend.friendship_id);
      }
      if (activeVisit) {
        recipientFriendships.set(activeVisit.host_account_id, activeVisit.friendship_id);
      }
      const recipients = [...recipientFriendships.entries()];
      const events = recipients.map(([recipientAccountID, friendshipID]) => accountEventFromMarkerStatement(db, {
        recipientAccountID,
        friendshipID,
        type: "pet.appearance.updated",
        aggregateType: "pet",
        aggregateID: context.petID,
        aggregateVersion: version,
        payload: { publicPetSnapshot: data },
        timelineVisible: false,
        occurredAt: now
      }, "pets", "appearance_version", context.petID, version));
      return {
        data,
        status: 200,
        notifyAccountIDs: recipients.map(([accountID]) => accountID),
        statements: [
          idempotencyStatement(
            db, context.accountID, "lockPetAppearance", context.petID,
            `catalog:${PET_APPEARANCE_CATALOG_VERSION}:${input.appearance.body}`,
            200, data, now
          ),
          db.prepare(`
            UPDATE pets SET appearance_schema_version = ?, appearance_catalog_version = ?,
              appearance_json = ?, appearance_version = ?, updated_at_ms = ?
            WHERE id = ? AND owner_account_id = ? AND appearance_version = ?
          `).bind(
            PET_APPEARANCE_SCHEMA_VERSION, PET_APPEARANCE_CATALOG_VERSION,
            JSON.stringify(appearance), version, now,
            context.petID, context.accountID, pet.appearance_version
          ),
          ...events,
          idempotencyFromMarkerStatement(
            db, context.accountID, "updatePetAppearance", idempotencyKey,
            fingerprint, 200, data, now, "pets", "appearance_version", context.petID, version
          )
        ]
      };
    },
    1
  );
  try {
    return await execute();
  } catch (error) {
    if (!isUniqueConstraintError(error)) throw error;
    // The lock row makes the first committed choice the winner even when two
    // D1 requests read the legacy row concurrently. Re-read after the losing
    // transaction rolls back, then converge or report the permanent lock.
    const authoritative = await db.prepare(`
      SELECT appearance_schema_version, appearance_catalog_version,
        appearance_json, appearance_version
      FROM pets WHERE id = ? AND owner_account_id = ?
    `).bind(context.petID, context.accountID).first<PetAppearanceRow>();
    if (!authoritative) throw notFound("pet");
    const character = selectedCharacter(authoritative);
    if (character === input.appearance.body) return execute();
    throw conflict(
      "appearance_locked",
      character === null
        ? "This pet appearance is already locked"
        : "This pet character was already selected on another device"
    );
  }
}
