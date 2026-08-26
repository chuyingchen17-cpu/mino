export type FriendshipStatus = "pending" | "accepted" | "rejected" | "closed";

export interface Friendship {
  id: string;
  requesterAccountID: string;
  addresseeAccountID: string;
  status: FriendshipStatus;
  version: number;
  createdAt: number;
  respondedAt: number | null;
  closedAt: number | null;
}

export interface FriendshipRow {
  id: string;
  requester_account_id: string;
  addressee_account_id: string;
  pair_key: string;
  status: FriendshipStatus;
  version: number;
  last_transition_id: string;
  created_at_ms: number;
  responded_at_ms: number | null;
  closed_at_ms: number | null;
}

export function friendshipFromRow(row: FriendshipRow): Friendship {
  return {
    id: row.id,
    requesterAccountID: row.requester_account_id,
    addresseeAccountID: row.addressee_account_id,
    status: row.status,
    version: row.version,
    createdAt: row.created_at_ms,
    respondedAt: row.responded_at_ms,
    closedAt: row.closed_at_ms
  };
}

export function pairKey(first: string, second: string): string {
  return [first, second].sort().join(":");
}
