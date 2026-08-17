import type { AuthContext, PetDecisionRequest, PetDecisionResponse } from "../domain.js";
import { AppError, badRequest, conflict, notFound } from "../errors.js";
import type { MinoStore, ModelInferenceFailure } from "../store.js";
import type { ModelProvider } from "./provider.js";

const ACTION_BY_DECISION = {
  idle: "idle",
  speak_to_owner: "speak_to_owner",
  send_pet_message: "send_pet_message",
  propose_visit: "propose_visit",
  respond_to_visit: "respond_to_visit",
  react_to_interaction: "react_to_interaction",
  request_return: "request_return"
} as const;

export class ModelDecisionService {
  private readonly processCache = new Map<string, { fingerprint: string; response: PetDecisionResponse }>();

  constructor(
    private readonly store: MinoStore,
    private readonly provider: ModelProvider
  ) {}

  async decide(context: AuthContext, request: PetDecisionRequest): Promise<PetDecisionResponse> {
    if (request.petID !== context.petID) throw notFound("pet");
    const cacheKey = `${context.accountID}:${request.inferenceID}`;
    const fingerprint = this.store.fingerprintRequest(request);
    const cached = this.processCache.get(cacheKey);
    if (cached) {
      if (cached.fingerprint !== fingerprint) {
        throw conflict("inference_id_reused", "The inference ID was already used with a different request");
      }
      return { ...cached.response, replayed: true };
    }

    const claim = await this.store.claimModelInference(
      context,
      request.inferenceID,
      this.provider.id,
      this.provider.model,
      fingerprint
    );
    if (claim.state === "replay") return claim.response;
    if (claim.state === "in_progress") {
      throw conflict("inference_in_progress", "This inference is already being processed; retry shortly");
    }
    if (claim.state === "outcome_unknown") {
      throw conflict(
        "inference_outcome_unknown",
        "The original model call may have completed; use a new inference ID instead of retrying it"
      );
    }
    if (claim.state === "failed") {
      throw new AppError(claim.failure.statusCode, claim.failure.code, claim.failure.message);
    }

    let response: PetDecisionResponse;
    try {
      const result = await this.provider.decide(request);
      const requiredAction = ACTION_BY_DECISION[result.decision.kind];
      if (!request.availableActions.includes(requiredAction)) {
        throw badRequest("disallowed_model_action", "The model selected an action that was not offered by the client");
      }
      if (
        (result.decision.kind === "send_pet_message" || result.decision.kind === "propose_visit") &&
        !this.allowedRecipientPetIDs(request).has(result.decision.recipientPetID)
      ) {
        throw badRequest("invalid_model_target", "The model selected a pet outside the supplied friend whitelist");
      }
      if (
        result.decision.kind === "respond_to_visit" &&
        result.decision.invitationID !== request.state.invitationID
      ) {
        throw badRequest("invalid_model_target", "The model selected a visit invitation outside the current event");
      }
      if (
        result.decision.kind === "request_return" &&
        ![request.state.visitID, request.state.currentEventVisitID].includes(result.decision.visitID)
      ) {
        throw badRequest("invalid_model_target", "The model selected a visit outside the current pet state");
      }
      response = {
        inferenceID: request.inferenceID,
        decision: result.decision,
        memoryDisposition: result.memoryDisposition,
        replayed: false,
        usage: result.usage
      };
    } catch (error) {
      const failure = this.modelFailure(error);
      await this.store.completeModelInference(context, request.inferenceID, "failed", 0, 0, undefined, failure);
      throw new AppError(failure.statusCode, failure.code, failure.message);
    }

    await this.store.completeModelInference(
      context,
      request.inferenceID,
      "completed",
      response.usage.inputTokens,
      response.usage.outputTokens,
      response
    );
    this.processCache.set(cacheKey, { fingerprint, response });
    if (this.processCache.size > 500) this.processCache.delete(this.processCache.keys().next().value!);
    return response;
  }

  private allowedRecipientPetIDs(request: PetDecisionRequest): Set<string> {
    if (request.state.friendPetIDs !== undefined) {
      return new Set(request.state.friendPetIDs);
    }
    return new Set(
      [request.state.targetPetID, request.state.senderPetID].filter(
        (petID): petID is string => typeof petID === "string"
      )
    );
  }

  private modelFailure(error: unknown): ModelInferenceFailure {
    if (error instanceof AppError) {
      return { statusCode: error.statusCode, code: error.code, message: error.message };
    }
    return {
      statusCode: 503,
      code: "model_unavailable",
      message: "The configured model provider is unavailable"
    };
  }
}
