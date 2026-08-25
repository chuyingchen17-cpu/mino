export type VisitStatus = "pending" | "active" | "closed";
export type VisitCloseReason =
  | "declined"
  | "cancelled"
  | "expired"
  | "recalled"
  | "sent_home"
  | "friendship_closed";

export interface Visit {
  id: string;
  friendshipID: string;
  visitorPetID: string;
  visitorOwnerAccountID: string;
  hostAccountID: string;
  requestedByAccountID: string;
  responderAccountID: string;
  status: VisitStatus;
  closeReason: VisitCloseReason | null;
  reason: string | null;
  version: number;
  createdAt: number;
  expiresAt: number;
  startedAt: number | null;
  closedAt: number | null;
}

export interface VisitRow {
  id: string;
  friendship_id: string;
  visitor_pet_id: string;
  visitor_owner_account_id: string;
  host_account_id: string;
  requested_by_account_id: string;
  responder_account_id: string;
  status: VisitStatus;
  close_reason: VisitCloseReason | null;
  reason: string | null;
  version: number;
  last_transition_id: string;
  created_at_ms: number;
  expires_at_ms: number;
  started_at_ms: number | null;
  closed_at_ms: number | null;
}

export function visitFromRow(row: VisitRow): Visit {
  return {
    id: row.id,
    friendshipID: row.friendship_id,
    visitorPetID: row.visitor_pet_id,
    visitorOwnerAccountID: row.visitor_owner_account_id,
    hostAccountID: row.host_account_id,
    requestedByAccountID: row.requested_by_account_id,
    responderAccountID: row.responder_account_id,
    status: row.status,
    closeReason: row.close_reason,
    reason: row.reason,
    version: row.version,
    createdAt: row.created_at_ms,
    expiresAt: row.expires_at_ms,
    startedAt: row.started_at_ms,
    closedAt: row.closed_at_ms
  };
}
