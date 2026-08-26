export type PetCareBand = "low" | "steady" | "high";
export type PetCareInteractionKind = "pet" | "feed" | "play" | "walk" | "rest" | "cuddle" | "flower";
export type PetInteractionOutcome = "applied" | "cosmetic_only" | "too_full" | "too_tired" | "resting_cooldown";

export interface PetCareState {
  fullness: number;
  energy: number;
  mood: number;
  bond: number;
  version: number;
  evaluatedAt: number;
}

export interface PublicPetCareSummary {
  fullness: PetCareBand;
  energy: PetCareBand;
  mood: PetCareBand;
}

export type PetFamiliarityTier = "first_meeting" | "recognized" | "familiar" | "close";

export interface PetFamiliarity {
  petID: string;
  friendshipID: string;
  score: number;
  tier: PetFamiliarityTier;
  version: number;
  updatedAt: number;
}

export interface PetCareEffect {
  fullness: number;
  energy: number;
  mood: number;
  bond: number;
  familiarity: number;
}

export interface PetInteractionReceipt {
  id: string;
  targetPetID: string;
  actorAccountID: string;
  friendshipID: string | null;
  visitID: string | null;
  kind: PetCareInteractionKind;
  outcome: PetInteractionOutcome;
  effect: PetCareEffect;
  careState: PetCareState | null;
  publicCare: PublicPetCareSummary;
  familiarity: PetFamiliarity | null;
  occurredAt: number;
}

export interface VisitInteractionSummary {
  counts: Partial<Record<PetCareInteractionKind, number>>;
  familiarityGained: number;
  letterAttached: boolean;
}

export interface PetCareRow {
  pet_id: string;
  fullness: number;
  energy: number;
  mood: number;
  bond: number;
  version: number;
  evaluated_at_ms: number;
  updated_at_ms: number;
}

export function careBand(value: number): PetCareBand {
  if (value <= 34) return "low";
  if (value <= 69) return "steady";
  return "high";
}

export function familiarityTier(score: number): PetFamiliarityTier {
  if (score <= 19) return "first_meeting";
  if (score <= 44) return "recognized";
  if (score <= 74) return "familiar";
  return "close";
}

export function careFromRow(row: PetCareRow, at = Date.now()): PetCareState {
  const elapsedDays = Math.max(0, at - row.evaluated_at_ms) / 86_400_000;
  const fullness = Math.max(35, row.fullness - Math.floor(elapsedDays * 20));
  const energy = Math.min(85, row.energy + Math.floor(elapsedDays * 20));
  const moodShift = Math.floor(elapsedDays * 10);
  const mood = row.mood > 60
    ? Math.max(60, row.mood - moodShift)
    : Math.min(60, row.mood + moodShift);
  return { fullness, energy, mood, bond: row.bond, version: row.version, evaluatedAt: at };
}

export function publicCare(state: PetCareState): PublicPetCareSummary {
  return {
    fullness: careBand(state.fullness),
    energy: careBand(state.energy),
    mood: careBand(state.mood)
  };
}

export function clamped(value: number): number {
  return Math.min(100, Math.max(0, value));
}
