import type { AuthContext, PublicPetSnapshot } from "../domain/models";
import type { Visit, VisitRow, VisitStatus } from "../domain/visit";
import { visitFromRow } from "../domain/visit";
import type { VisitAction, VisitActionRow } from "../domain/visit-action";
import { visitActionFromRow } from "../domain/visit-action";
import { notFound } from "../errors";
import { publicPetFromRow } from "./accounts-repository";

export async function findVisit(
  db: D1Database,
  context: AuthContext,
  visitID: string
): Promise<Visit> {
  const row = await db.prepare(`
    SELECT visits.* FROM visits
    JOIN friendships ON friendships.id = visits.friendship_id
    WHERE visits.id = ?
      AND ? IN (friendships.requester_account_id, friendships.addressee_account_id)
  `).bind(visitID, context.accountID).first<VisitRow>();
  if (!row) throw notFound("visit");
  return visitFromRow(row);
}

export async function listVisits(
  db: D1Database,
  context: AuthContext,
  status?: VisitStatus
): Promise<Visit[]> {
  const statusFilter = status ? "AND visits.status = ?" : "";
  const statement = db.prepare(`
    SELECT visits.* FROM visits
    JOIN friendships ON friendships.id = visits.friendship_id
    WHERE ? IN (friendships.requester_account_id, friendships.addressee_account_id)
      ${statusFilter}
    ORDER BY visits.created_at_ms DESC, visits.id DESC
  `);
  const rows = status
    ? await statement.bind(context.accountID, status).all<VisitRow>()
    : await statement.bind(context.accountID).all<VisitRow>();
  return rows.results.map(visitFromRow);
}

export async function publicPetSnapshot(db: D1Database, petID: string): Promise<PublicPetSnapshot> {
  const row = await db.prepare("SELECT * FROM pets WHERE id = ?").bind(petID).first<{
    id: string;
    display_name: string;
    appearance_schema_version: number;
    appearance_catalog_version: number;
    appearance_json: string;
    appearance_version: number;
  }>();
  if (!row) throw notFound("pet");
  return publicPetFromRow(row);
}

export async function listUnresolvedVisitActions(
  db: D1Database,
  context: AuthContext
): Promise<VisitAction[]> {
  const rows = await db.prepare(`
    SELECT action.* FROM visit_actions AS action
    JOIN visits ON visits.id = action.visit_id
    WHERE visits.status = 'active'
      AND visits.visitor_owner_account_id = ?
      AND action.requires_response = 1
      AND NOT EXISTS (
        SELECT 1 FROM visit_actions AS reply WHERE reply.reply_to_action_id = action.id
      )
    ORDER BY action.created_at_ms ASC, action.id ASC
  `).bind(context.accountID).all<VisitActionRow>();
  return rows.results.map(visitActionFromRow);
}

export async function findVisitAction(
  db: D1Database,
  visitID: string,
  actionID: string
): Promise<VisitAction | null> {
  const row = await db.prepare("SELECT * FROM visit_actions WHERE id = ? AND visit_id = ?")
    .bind(actionID, visitID).first<VisitActionRow>();
  return row ? visitActionFromRow(row) : null;
}
