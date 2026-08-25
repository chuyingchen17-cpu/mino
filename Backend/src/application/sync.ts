import type { AuthContext } from "../domain/models";
import { friendshipFromRow, type FriendshipRow } from "../domain/friendship";
import { visitFromRow, type VisitRow } from "../domain/visit";
import { visitActionFromRow, type VisitActionRow } from "../domain/visit-action";
import { notFound } from "../errors";
import { publicPetFromRow } from "../storage/accounts-repository";
import { careFromRow, familiarityTier, publicCare, type PetCareRow } from "../domain/pet-care";

interface AccountRow {
  id: string;
  display_name: string;
  primary_agent_device_id: string | null;
  created_at_ms: number;
  updated_at_ms: number;
}

interface DeviceRow {
  id: string;
  account_id: string;
  display_name: string;
  platform: "macos";
  app_version: string;
  created_at_ms: number;
  revoked_at_ms: number | null;
}

interface PetRow {
  id: string;
  display_name: string;
  appearance_schema_version: number;
  appearance_catalog_version: number;
  appearance_json: string;
  appearance_version: number;
}

interface FriendshipBootstrapRow extends FriendshipRow {
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

interface ConversationRow {
  id: string;
  friendship_id: string;
  initiator_pet_id: string;
  recipient_pet_id: string;
  status: "active" | "ended";
  next_speaker_pet_id: string | null;
  turn_count: number;
  version: number;
  created_at_ms: number;
  ended_at_ms: number | null;
}

interface PetFamiliarityRow {
  pet_id: string;
  friendship_id: string;
  score: number;
  version: number;
  updated_at_ms: number;
}

function results<T>(result: D1Result<unknown>): T[] {
  return result.results as T[];
}

export async function syncBootstrap(db: D1Database, context: AuthContext, now = Date.now()) {
  const batch = await db.batch([
    db.prepare("SELECT id, display_name, primary_agent_device_id, created_at_ms, updated_at_ms FROM accounts WHERE id = ?")
      .bind(context.accountID),
    db.prepare("SELECT * FROM devices WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL")
      .bind(context.deviceID, context.accountID),
    db.prepare("SELECT * FROM pets WHERE id = ? AND owner_account_id = ?")
      .bind(context.petID, context.accountID),
    db.prepare(`
      SELECT friendships.*,
        friend.id AS friend_account_id, friend.display_name AS friend_display_name,
        friend_pet.id AS friend_pet_id, friend_pet.display_name AS friend_pet_name,
        friend_pet.appearance_schema_version, friend_pet.appearance_catalog_version,
        friend_pet.appearance_json, friend_pet.appearance_version,
        care.fullness AS care_fullness, care.energy AS care_energy,
        care.mood AS care_mood, care.bond AS care_bond,
        care.version AS care_version, care.evaluated_at_ms AS care_evaluated_at_ms,
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
        AND friendships.status IN ('pending', 'accepted')
      ORDER BY friendships.created_at_ms DESC
    `).bind(context.accountID, context.accountID),
    db.prepare(`
      SELECT visits.* FROM visits JOIN friendships ON friendships.id = visits.friendship_id
      WHERE visits.status = 'pending'
        AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
      ORDER BY visits.created_at_ms ASC
    `).bind(context.accountID),
    db.prepare(`
      SELECT visits.* FROM visits JOIN friendships ON friendships.id = visits.friendship_id
      WHERE visits.status = 'active'
        AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
      ORDER BY visits.created_at_ms ASC
    `).bind(context.accountID),
    db.prepare(`
      SELECT action.* FROM visit_actions AS action
      JOIN visits ON visits.id = action.visit_id
      WHERE visits.status = 'active' AND visits.visitor_owner_account_id = ?
        AND action.requires_response = 1
        AND NOT EXISTS (SELECT 1 FROM visit_actions reply WHERE reply.reply_to_action_id = action.id)
      ORDER BY action.created_at_ms ASC
    `).bind(context.accountID),
    db.prepare(`
      SELECT conversations.* FROM conversations
      JOIN friendships ON friendships.id = conversations.friendship_id
      WHERE conversations.status = 'active'
        AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
      ORDER BY conversations.created_at_ms DESC
    `).bind(context.accountID),
    db.prepare("SELECT COALESCE(MAX(sequence), 0) AS cursor FROM account_events WHERE recipient_account_id = ?")
      .bind(context.accountID),
    db.prepare("SELECT * FROM pet_care_states WHERE pet_id = ?")
      .bind(context.petID),
    db.prepare("SELECT * FROM pet_familiarities WHERE pet_id = ? ORDER BY friendship_id")
      .bind(context.petID)
  ]);

  const account = results<AccountRow>(batch[0]!)[0];
  const device = results<DeviceRow>(batch[1]!)[0];
  const pet = results<PetRow>(batch[2]!)[0];
  if (!account || !device || !pet) throw notFound("account");
  const friendships = results<FriendshipBootstrapRow>(batch[3]!).map((row) => {
    const care = careFromRow({
      pet_id: row.friend_pet_id,
      fullness: row.care_fullness ?? 70,
      energy: row.care_energy ?? 80,
      mood: row.care_mood ?? 70,
      bond: row.care_bond ?? 20,
      version: row.care_version ?? 1,
      evaluated_at_ms: row.care_evaluated_at_ms ?? now,
      updated_at_ms: row.care_updated_at_ms ?? now
    }, now);
    return {
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
      },
      ...(row.familiarity_score !== null ? {
        familiarity: {
          petID: row.friend_pet_id,
          friendshipID: row.id,
          score: row.familiarity_score,
          tier: familiarityTier(row.familiarity_score),
          version: row.familiarity_version ?? 1,
          updatedAt: row.familiarity_updated_at_ms ?? now
        }
      } : {})
    };
  });
  const ownCareRow = results<PetCareRow>(batch[9]!)[0] ?? {
    pet_id: context.petID,
    fullness: 70,
    energy: 80,
    mood: 70,
    bond: 20,
    version: 1,
    evaluated_at_ms: now,
    updated_at_ms: now
  };
  return {
    account: {
      id: account.id,
      displayName: account.display_name,
      primaryAgentDeviceID: account.primary_agent_device_id,
      createdAt: account.created_at_ms,
      updatedAt: account.updated_at_ms
    },
    currentDevice: {
      id: device.id,
      accountID: device.account_id,
      displayName: device.display_name,
      platform: device.platform,
      appVersion: device.app_version,
      createdAt: device.created_at_ms,
      revokedAt: device.revoked_at_ms
    },
    isPrimaryAgentDevice: account.primary_agent_device_id === device.id,
    pet: publicPetFromRow(pet),
    ownPetCare: careFromRow(ownCareRow, now),
    petFamiliarities: results<PetFamiliarityRow>(batch[10]!).map((row) => ({
      petID: row.pet_id,
      friendshipID: row.friendship_id,
      score: row.score,
      tier: familiarityTier(row.score),
      version: row.version,
      updatedAt: row.updated_at_ms
    })),
    friendships,
    pendingVisits: results<VisitRow>(batch[4]!).map(visitFromRow),
    activeVisits: results<VisitRow>(batch[5]!).map(visitFromRow),
    unresolvedVisitActions: results<VisitActionRow>(batch[6]!).map(visitActionFromRow),
    activeConversations: results<ConversationRow>(batch[7]!).map((row) => ({
      id: row.id,
      friendshipID: row.friendship_id,
      initiatorPetID: row.initiator_pet_id,
      recipientPetID: row.recipient_pet_id,
      status: row.status,
      nextSpeakerPetID: row.next_speaker_pet_id,
      turnCount: row.turn_count,
      version: row.version,
      createdAt: row.created_at_ms,
      endedAt: row.ended_at_ms
    })),
    cursor: results<{ cursor: number }>(batch[8]!)[0]?.cursor ?? 0,
    serverTime: now
  };
}
