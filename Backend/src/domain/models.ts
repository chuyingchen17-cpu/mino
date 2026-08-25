import type { Friendship } from "./friendship";
import type { PetFamiliarity, PublicPetCareSummary } from "./pet-care";

export interface AuthContext {
  accountID: string;
  deviceID: string;
  petID: string;
  isPrimaryAgentDevice: boolean;
  sessionID: string;
}

export interface Device {
  id: string;
  accountID: string;
  displayName: string;
  platform: "macos";
  appVersion: string;
  createdAt: number;
  revokedAt: number | null;
}

export interface PublicPetSnapshot {
  petID: string;
  displayName: string;
  appearanceSchemaVersion: number;
  appearanceCatalogVersion: number;
  appearanceVersion: number;
  appearance: Record<string, string>;
  publicCare?: PublicPetCareSummary;
}

export interface FriendshipSummary extends Friendship {
  friend: {
    accountID: string;
    displayName: string;
    pet: PublicPetSnapshot;
  };
  familiarity?: PetFamiliarity;
}

export interface MutationResult<T> {
  data: T;
  status: number;
  notifyAccountIDs: string[];
  replayed: boolean;
}
