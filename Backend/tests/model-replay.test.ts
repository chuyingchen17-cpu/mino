import { randomUUID } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PetDecisionRequest } from "../src/domain.js";
import { InMemoryMinoStore } from "../src/memory-store.js";
import type { ModelDecisionResult, ModelProvider } from "../src/model/provider.js";
import { ModelDecisionService } from "../src/model/service.js";

class CountingProvider implements ModelProvider {
  readonly id = "counting-test";
  readonly model = "counting-v1";
  calls = 0;

  async decide(): Promise<ModelDecisionResult> {
    this.calls += 1;
    return {
      decision: { kind: "idle" },
      memoryDisposition: { kind: "discard" },
      usage: { inputTokens: 17, outputTokens: 3 }
    };
  }
}

afterEach(() => vi.useRealTimers());

describe("durable model inference claims", () => {
  it("replays the original decision and usage across service instances", async () => {
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const context = await store.authenticate(profiles.alice.token);
    expect(context).not.toBeNull();
    const provider = new CountingProvider();
    const request: PetDecisionRequest = {
      inferenceID: randomUUID(),
      petID: context!.petID,
      trigger: { type: "periodic_wake", summary: "test" },
      state: {},
      memories: [],
      availableActions: ["idle"]
    };

    const first = await new ModelDecisionService(store, provider).decide(context!, request);
    const replay = await new ModelDecisionService(store, provider).decide(context!, request);

    expect(provider.calls).toBe(1);
    expect(first.replayed).toBe(false);
    expect(replay).toEqual({ ...first, replayed: true });
    expect(replay.usage).toEqual({ inputTokens: 17, outputTokens: 3 });
  });

  it("rejects reuse of an inference ID with a different request", async () => {
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const context = await store.authenticate(profiles.alice.token);
    const provider = new CountingProvider();
    const inferenceID = randomUUID();
    const first: PetDecisionRequest = {
      inferenceID,
      petID: context!.petID,
      trigger: { type: "periodic_wake", summary: "first" },
      state: {},
      memories: [],
      availableActions: ["idle"]
    };
    const changed = { ...first, trigger: { type: "periodic_wake", summary: "changed" } } as PetDecisionRequest;

    await new ModelDecisionService(store, provider).decide(context!, first);
    await expect(new ModelDecisionService(store, provider).decide(context!, changed))
      .rejects.toMatchObject({ statusCode: 409, code: "inference_id_reused" });
    expect(provider.calls).toBe(1);
  });

  it("persists a model failure and does not call the provider again", async () => {
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const context = await store.authenticate(profiles.alice.token);
    let calls = 0;
    const provider: ModelProvider = {
      id: "failing",
      model: "failing-v1",
      async decide() {
        calls += 1;
        throw new Error("upstream disconnected after accepting the request");
      }
    };
    const request: PetDecisionRequest = {
      inferenceID: randomUUID(),
      petID: context!.petID,
      trigger: { type: "periodic_wake", summary: "failure" },
      state: {},
      memories: [],
      availableActions: ["idle"]
    };

    await expect(new ModelDecisionService(store, provider).decide(context!, request))
      .rejects.toMatchObject({ statusCode: 503, code: "model_unavailable" });
    await expect(new ModelDecisionService(store, provider).decide(context!, request))
      .rejects.toMatchObject({ statusCode: 503, code: "model_unavailable" });
    expect(calls).toBe(1);
  });

  it("blocks a live claim and never reclaims an uncertain charged call", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-16T00:00:00.000Z"));
    const store = new InMemoryMinoStore();
    const profiles = await store.bootstrapDevProfiles();
    const context = await store.authenticate(profiles.alice.token);
    const inferenceID = randomUUID();
    const fingerprint = store.fingerprintRequest({ inferenceID });

    await expect(store.claimModelInference(context!, inferenceID, "mock", "v1", fingerprint, 60_000))
      .resolves.toEqual({ state: "claimed" });
    await expect(store.claimModelInference(context!, inferenceID, "mock", "v1", fingerprint, 60_000))
      .resolves.toEqual({ state: "in_progress" });

    vi.advanceTimersByTime(60_001);
    await expect(store.claimModelInference(context!, inferenceID, "mock", "v1", fingerprint, 60_000))
      .resolves.toEqual({ state: "outcome_unknown" });
  });
});
