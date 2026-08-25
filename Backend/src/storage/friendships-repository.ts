import type { FriendshipRow, FriendshipStatus } from "../domain/friendship";
import { friendshipFromRow } from "../domain/friendship";
import type { AuthContext, FriendshipSummary } from "../domain/models";
import { notFound } from "../errors";
import { publicPetFromRow } from "./accounts-repository";
import { careFromRow, familiarityTier, publicCare, type PetCareRow } from "../domain/pet-care";

export interface FriendshipAccess {
  row: FriendshipRow;
  friendAccountID: string;
  friendPetID: string;
}

interface SummaryRow extends FriendshipRow {
  friend_account_id: string;
  friend_display_name: string;
  friend_pet_id: string;
  friend_pet_name: string;
  appearance_schema_version: number;
  appearance_catalog_version: number;
  appearance_json: string;
  appearance_version: number;
  care_fullness: number | null;
  care_energy: number | null;
  care_mood: number | null;
  care_bond: number | null;
  care_version: number | null;
  care_evaluated_at_ms: number | null;
  care_updated_at_ms: number | null;
  familiarity_score: number | null;
  familiarity_version: number | null;
  familiarity_updated_at_ms: number | null;
}

function summaryFromRow(row: SummaryRow, now: number): FriendshipSummary {
  const care = careFromRow({
    pet_id: row.friend_pet_id,
    fullness: row.care_fullness ?? 70,
    energy: row.care_energy ?? 80,
    mood: row.care_mood ?? 70,
    bond: row.care_bond ?? 20,
    version: row.care_version ?? 1,
    evaluated_at_ms: row.care_evaluated_at_ms ?? now,
    updated_at_ms: row.care_updated_at_ms ?? now
  } satisfies PetCareRow, now);
  const summary: FriendshipSummary = {
    ...friendshipFromRow(row),
    friend: {
      accountID: row.friend_account_id,
      displayName: row.friend_display_name,
      pet: {
        ...publicPetFromRow({
        id: row.friend_pet_id,
        display_name: row.friend_pet_name,
        appearance_schema_version: row.appearance_schema_version,
        appearance_catalog_version: row.appearance_catalog_version,
        appearance_json: row.appearance_json,
          appearance_version: row.appearance_version
        }),
        publicCare: publicCare(care)
      }
    }
  };
  if (row.familiarity_score !== null) {
    summary.familiarity = {
      petID: row.friend_pet_id,
      friendshipID: row.id,
      score: row.familiarity_score,
      tier: familiarityTier(row.familiarity_score),
      version: row.familiarity_version ?? 1,
      updatedAt: row.familiarity_updated_at_ms ?? now
    };
  }
  return summary;
}

export async function listFriendships(
  db: D1Database,
  context: AuthContext,
  status?: FriendshipStatus
): Promise<FriendshipSummary[]> {
  const statusFilter = status ? "AND friendships.status = ?" : "";
  const statement = db.prepare(`
    SELECT friendships.*,
      friend.id AS friend_account_id,
      friend.display_name AS friend_display_name,
      friend_pet.id AS friend_pet_id,
      friend_pet.display_name AS friend_pet_name,
      friend_pet.appearance_schema_version,
      friend_pet.appearance_catalog_version,
      friend_pet.appearance_json,
      friend_pet.appearance_version,
      care.fullness AS care_fullness,
      care.energy AS care_energy,
      care.mood AS care_mood,
      care.bond AS care_bond,
      care.version AS care_version,
      care.evaluated_at_ms AS care_evaluated_at_ms,
      care.updated_at_ms AS care_updated_at_ms,
      familiarity.score AS familiarity_score,
      familiarity.version AS familiarity_version,
      familiarity.updated_at_ms AS familiarity_updated_at_ms
    FROM friendships
    JOIN accounts AS friend ON friend.id = CASE
      WHEN friendships.requester_account_id = ? THEN friendships.addressee_account_id
      ELSE friendships.requester_account_id END
    JOIN pets AS friend_pet ON friend_pet.owner_account_id = friend.id
    LEFT JOIN pet_care_states AS care ON care.pet_id = friend_pet.id
    LEFT JOIN pet_familiarities AS familiarity
      ON familiarity.pet_id = friend_pet.id AND familiarity.friendship_id = friendships.id
    WHERE ? IN (friendships.requester_account_id, friendships.addressee_account_id)
      ${statusFilter}
    ORDER BY friendships.created_at_ms DESC, friendships.id DESC
  `);
  const bound = status
    ? statement.bind(context.accountID, context.accountID, status)
    : statement.bind(context.accountID, context.accountID);
  const rows = await bound.all<SummaryRow>();
  const now = Date.now();
  return rows.results.map((row) => summaryFromRow(row, now));
}

export async function requireFriendship(
  db: D1Database,
  context: AuthContext,
  friendshipID: string,
  accepted = false
): Promise<FriendshipAccess> {
  const acceptedFilter = accepted ? "AND friendships.status = 'accepted'" : "";
  const row = await db.prepare(`
    SELECT friendships.*,
      CASE WHEN requester_account_id = ? THEN addressee_account_id ELSE requester_account_id END AS friend_account_id,
      friend_pet.id AS friend_pet_id
    FROM friendships
    JOIN pets AS friend_pet ON friend_pet.owner_account_id = CASE
      WHEN requester_account_id = ? THEN addressee_account_id ELSE requester_account_id END
    WHERE friendships.id = ?
      AND ? IN (requester_account_id, addressee_account_id)
      ${acceptedFilter}
  `).bind(context.accountID, context.accountID, friendshipID, context.accountID)
    .first<FriendshipRow & { friend_account_id: string; friend_pet_id: string }>();
  if (!row) throw notFound("friendship");
  return { row, friendAccountID: row.friend_account_id, friendPetID: row.friend_pet_id };
}

export async function friendshipSummary(
  db: D1Database,
  context: AuthContext,
  friendshipID: string
): Promise<FriendshipSummary> {
  const values = await listFriendships(db, context);
  const summary = values.find((candidate) => candidate.id === friendshipID);
  if (!summary) throw notFound("friendship");
  return summary;
}
