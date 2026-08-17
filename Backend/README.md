# Mino Backend MVP

Single-process Fastify service for local macOS pet Agents. Every account owns one pet and may connect to multiple accounts through explicit friendships. PostgreSQL is the only durable server-side dependency; Redis and background workers are intentionally not used.

## Local development

```sh
cp .env.example .env
docker compose up -d postgres
npm install
npm run db:migrate
npm run dev
```

The API is available at `http://127.0.0.1:8080/v1`. Root routes are also registered for compatibility. Check either `/health` or `/v1/health`.

Create the isolated local identities with:

```sh
curl -sS http://127.0.0.1:8080/v1/dev/bootstrap \
  -H 'content-type: application/json' \
  -d '{"profile":"alice"}'
```

Repeat with `bob`. `charlie` is also available to exercise the friendship request flow. Alice and Bob start as accepted friends; Charlie starts with no friends. The returned bearer tokens are deterministic, public local-development credentials, so local Keychain sessions remain valid after a service restart. They are not secrets and must never be used outside local development. `/dev/bootstrap` is disabled unless `DEV_BOOTSTRAP_ENABLED=true`; production startup rejects that setting and the PostgreSQL store rejects these known development tokens.

For production, set `LETTER_ENCRYPTION_KEY` to the Base64 encoding of exactly 32 random bytes and keep it in the deployment secret store. Development derives a stable local-only key from `DATABASE_URL` when the variable is absent. Losing or changing the key makes encrypted letters unreadable.

## Commands

- `npm run typecheck` — strict TypeScript check.
- `npm test` — route and state-machine tests using the in-memory store; no database or network required.
- `RUN_POSTGRES_TESTS=true DATABASE_URL=postgres://… npm test -- tests/postgres.integration.test.ts` — opt-in real PostgreSQL coverage. Each test migrates and drops only its own random schema; the database role needs schema-create permission.
- `npm run build` — compile the server and migrations into `dist/`.
- `npm run db:migrate` — apply PostgreSQL migrations.
- `npm run db:rollback` — roll back one migration.

## Runtime model

- `accounts` own pets independently of relationships. `friendships` is the authority for cross-account access; legacy `couples/couple_id` values remain only as internal storage scopes so existing databases can migrate without rewriting historical resources.
- Friendship APIs are `GET /friendships`, `POST /friendships`, and `POST /friendships/:friendshipID/respond`. Only the addressee can accept or reject. Rejected pairs may apply again, while a pending or accepted pair is unique.
- HTTP business writes commit the state change, durable friendship event, and idempotency receipt in one PostgreSQL transaction.
- Every idempotency receipt records a canonical request fingerprint. An exact retry replays the first result; the same key with a different payload returns `409 idempotency_key_reused`.
- Cross-account routes accept `friendshipID` as a query parameter. For compatibility it may be omitted only when the account has exactly one accepted friendship; otherwise the server returns `409 friendship_context_required`.
- `/events` and `/timeline` are deliberately friendship-scoped, not account-global. A personal timeline client lists accepted friendships, catches up each friendship with its own cursor, and merges the resulting events by `occurredAt` (using `sequence` as a stable tie-breaker). Event inserts hold a friendship-scoped PostgreSQL transaction lock from sequence allocation through commit, so a later visible cursor cannot overtake an earlier uncommitted event. Pending friendship requests are state from `GET /friendships?status=pending`, not social timeline events. This keeps cursor authorization and relationship privacy explicit without introducing a second account-event store in the MVP.
- WebSocket only accelerates delivery. Clients recover missed events with `GET /events?friendshipID=<id>&after=<eventID>`. `/ws?friendshipID=<id>&after=<eventID>` also replays the handoff gap while buffering concurrent publications, so an event cannot disappear between REST catch-up and subscription. Empty pages preserve the requested cursor; malformed UUIDs return 400 and unknown or cross-friendship cursor IDs return 404.
- The server stores only logical pet residence (`home` is derived when no active visit exists; otherwise the visitor is `visiting`). Presence checks active visits globally, but a friendship snapshot exposes `hostAccountID` and `activeVisitID` only for a visit in that friendship; another friendship sees only that the pet is away. Screen coordinates and animation remain local.
- A visitor pet and a host account can each participate in at most one active visit globally, enforced by partial unique PostgreSQL indexes.
- Only the account opposite `requestedByAccountID` can answer a visit invitation: the host answers a visitor-owner request, and the visitor owner answers a host request. Invitation events carry both account IDs for deterministic client routing.
- A friendship has at most one active pet conversation. Clients restore it after restart through `GET /conversations?friendshipID=<id>&status=active` and rebuild the transcript with `GET /conversations/:id/messages?friendshipID=<id>`. Pet conversations stop after the sixth pet message without a server-authored summary. The initiating pet's owner then runs its local Agent and is the only party allowed to submit the first timeline summary through `/conversations/:id/end`, even though the conversation is already ended.
- Host interactions travel to the visitor's owner Agent; its response returns through `POST /visits/:visitID/reactions` and is never generated by the server.
- Agent requests may supply all accepted targets in `state.friendPetIDs`. The server verifies every ID against current friendships before calling the model, and rejects any social decision whose recipient falls outside that request-scoped whitelist. `targetPetID` and `senderPetID` remain event-context hints rather than authorization.
- The deterministic development model sends a `send_pet_message` decision on `periodic_wake`, an `excited` visitor reaction on `visit_started`, and a concise summary-style `speak_to_owner` decision on `conversation_ended` when those actions are offered. Thus an offline visitor remains asleep; an online origin Agent explicitly wakes the host animation through the reaction endpoint.
- Model prompts, raw provider responses, and pet memories are not persisted. The validated decision, memory disposition, and usage are stored by `inferenceID`, making retries and restarts replay the original response without a second charge. The ID is bound to a keyed request fingerprint; a different request cannot reuse it. A concurrent live claim returns `409 inference_in_progress`, while a stale started claim returns `409 inference_outcome_unknown` and is never sent upstream again under that ID. Provider calls also carry the inference ID as an idempotency header when supported.
- Human letter bodies are stored as AES-256-GCM ciphertext in both `letters.body` and idempotency receipts. Event payloads contain only ID/routing metadata, never the body. The recipient reads the decrypted body through `GET /letters/:letterID` only after delivery. Agent requests use a strict state allowlist, reject letter-shaped fields and memories, and only accept the sealed-letter trigger with its fixed body-free summary.
- Legacy `POST /pet-visits` is deprecated and returns `409 visit_invitation_required` before writing anything; callers must use the two-party invitation handshake.

The full wire contract and event payload conventions are in [openapi.yaml](./openapi.yaml).
