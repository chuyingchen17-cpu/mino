export type VisitActionActorType = "human" | "pet_agent" | "system";
export type HostVisitActionKind = "feed" | "play" | "pet" | "hug" | "kiss" | "flower" | "walk" | "message";
export type AgentVisitActionKind = "reaction" | "activity" | "speech" | "acknowledgement";
export type VisitActionKind = HostVisitActionKind | AgentVisitActionKind;

export interface VisitAction {
  id: string;
  visitID: string;
  senderAccountID: string;
  actorType: VisitActionActorType;
  kind: VisitActionKind;
  payload: Record<string, unknown>;
  replyToActionID: string | null;
  requiresResponse: boolean;
  createdAt: number;
}

export interface VisitActionRow {
  id: string;
  visit_id: string;
  sender_account_id: string;
  actor_type: VisitActionActorType;
  kind: VisitActionKind;
  payload_json: string;
  reply_to_action_id: string | null;
  requires_response: number;
  created_at_ms: number;
}

export function visitActionFromRow(row: VisitActionRow): VisitAction {
  return {
    id: row.id,
    visitID: row.visit_id,
    senderAccountID: row.sender_account_id,
    actorType: row.actor_type,
    kind: row.kind,
    payload: JSON.parse(row.payload_json) as Record<string, unknown>,
    replyToActionID: row.reply_to_action_id,
    requiresResponse: row.requires_response === 1,
    createdAt: row.created_at_ms
  };
}
