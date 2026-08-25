#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
api_base_url="${MINO_API_BASE_URL:-http://127.0.0.1:8787}"
backend_port="${api_base_url##*:}"
backend_pid=""
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/mino-smoke.XXXXXX")"

cleanup() {
    if [[ -n "$backend_pid" ]]; then
        kill "$backend_pid" 2>/dev/null || true
    fi
    rm -rf "$scratch_dir"
}
trap cleanup EXIT INT TERM

for command_name in curl npm node; do
    if (( ! $+commands[$command_name] )); then
        echo "Required command is unavailable: $command_name" >&2
        exit 2
    fi
done

if [[ ! "$api_base_url" =~ '^http://(127\.0\.0\.1|localhost):[0-9]+$' ]]; then
    echo "MINO_API_BASE_URL must be an explicit loopback URL." >&2
    exit 2
fi

if ! curl --fail --silent "$api_base_url/v1/health" >/dev/null 2>&1; then
    if [[ ! -d "$project_dir/Backend/node_modules" ]]; then
        npm --prefix "$project_dir/Backend" ci
    fi
    npm --prefix "$project_dir/Backend" run db:migrate:local >/dev/null
    (
        cd "$project_dir/Backend"
        npm run dev -- \
            --ip 127.0.0.1 \
            --port "$backend_port" \
            --var GITHUB_CLIENT_ID:Ov23liZNdBaSHLQpJkIn \
            --var SESSION_TOKEN_PEPPER:mino-local-session-pepper \
            --var LETTER_ENCRYPTION_KEY_V1:MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY= \
            --var MODEL_PROVIDER_API_KEY:local-mock >"$scratch_dir/worker.log" 2>&1
    ) &
    backend_pid=$!
    for _ in {1..30}; do
        curl --fail --silent "$api_base_url/v1/health" >/dev/null 2>&1 && break
        sleep 1
    done
    if ! curl --fail --silent "$api_base_url/v1/health" >/dev/null 2>&1; then
        cat "$scratch_dir/worker.log" >&2
        echo "Local Worker did not become healthy." >&2
        exit 1
    fi
fi

json_value() {
    node -e 'const value = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const path = process.argv[2].split("."); let cursor = value; for (const part of path) cursor = cursor[part]; process.stdout.write(String(cursor));' "$1" "$2"
}

new_key() {
    node -e 'process.stdout.write(crypto.randomUUID())'
}

curl --fail --silent --show-error "$api_base_url/v1/dev/bootstrap" \
    -H 'content-type: application/json' -d '{"profile":"alice"}' >"$scratch_dir/alice.json"
curl --fail --silent --show-error "$api_base_url/v1/dev/bootstrap" \
    -H 'content-type: application/json' -d '{"profile":"bob"}' >"$scratch_dir/bob.json"

alice_token="$(json_value "$scratch_dir/alice.json" data.token)"
alice_account="$(json_value "$scratch_dir/alice.json" data.accountID)"
alice_pet="$(json_value "$scratch_dir/alice.json" data.petID)"
bob_token="$(json_value "$scratch_dir/bob.json" data.token)"
bob_account="$(json_value "$scratch_dir/bob.json" data.accountID)"
bob_pet="$(json_value "$scratch_dir/bob.json" data.petID)"
friendship_id="$(json_value "$scratch_dir/alice.json" data.friends.0.friendshipID)"

node -e 'process.stdout.write(JSON.stringify({friendshipID:process.argv[1],visitorPetID:process.argv[2],hostAccountID:process.argv[3],reason:"dual-profile smoke"}))' \
    "$friendship_id" "$alice_pet" "$bob_account" >"$scratch_dir/create-body.json"
curl --fail --silent --show-error "$api_base_url/v1/visits" \
    -H "authorization: Bearer $alice_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' --data-binary "@$scratch_dir/create-body.json" >"$scratch_dir/visit.json"
visit_id="$(json_value "$scratch_dir/visit.json" data.id)"

curl --fail --silent --show-error "$api_base_url/v1/visits/$visit_id/respond" \
    -H "authorization: Bearer $bob_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' -d '{"response":"accept","actorType":"human"}' >"$scratch_dir/accepted.json"

node -e 'process.stdout.write(JSON.stringify({kind:"feed",visitID:process.argv[1],occurredAt:Date.now()}))' \
    "$visit_id" >"$scratch_dir/care-body.json"
curl --fail --silent --show-error "$api_base_url/v1/pets/$alice_pet/interactions" \
    -H "authorization: Bearer $bob_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' --data-binary "@$scratch_dir/care-body.json" >"$scratch_dir/care.json"
curl --fail --silent --show-error "$api_base_url/v1/visits/$visit_id/letters" \
    -H "authorization: Bearer $bob_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' -d '{"body":"下次再一起散步。"}' >"$scratch_dir/letter.json"
curl --fail --silent --show-error "$api_base_url/v1/visits/$visit_id/end" \
    -H "authorization: Bearer $alice_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' -d '{"actorType":"human"}' >"$scratch_dir/ended.json"

# Reverse direction: Alice invites Bob's pet to Alice's desktop, and Bob
# explicitly declines. This verifies that direction and decision are human-owned.
node -e 'process.stdout.write(JSON.stringify({friendshipID:process.argv[1],visitorPetID:process.argv[2],hostAccountID:process.argv[3],reason:"reverse direction smoke"}))' \
    "$friendship_id" "$bob_pet" "$alice_account" >"$scratch_dir/reverse-body.json"
curl --fail --silent --show-error "$api_base_url/v1/visits" \
    -H "authorization: Bearer $alice_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' --data-binary "@$scratch_dir/reverse-body.json" >"$scratch_dir/reverse.json"
reverse_visit_id="$(json_value "$scratch_dir/reverse.json" data.id)"
curl --fail --silent --show-error "$api_base_url/v1/visits/$reverse_visit_id/respond" \
    -H "authorization: Bearer $bob_token" -H "idempotency-key: $(new_key)" \
    -H 'content-type: application/json' -d '{"response":"decline","actorType":"human"}' >"$scratch_dir/declined.json"

curl --fail --silent --show-error "$api_base_url/v1/events?after=0&limit=100" \
    -H "authorization: Bearer $alice_token" >"$scratch_dir/alice-events.json"
curl --fail --silent --show-error "$api_base_url/v1/events?after=0&limit=100" \
    -H "authorization: Bearer $bob_token" >"$scratch_dir/bob-events.json"
curl --fail --silent --show-error "$api_base_url/v1/events?after=0&limit=100&timelineVisible=true" \
    -H "authorization: Bearer $alice_token" >"$scratch_dir/alice-timeline.json"

node -e '
const fs = require("fs");
const ended = JSON.parse(fs.readFileSync(process.argv[1])).data;
const alice = JSON.parse(fs.readFileSync(process.argv[2])).data.events;
const bob = JSON.parse(fs.readFileSync(process.argv[3])).data.events;
const care = JSON.parse(fs.readFileSync(process.argv[4])).data;
const declined = JSON.parse(fs.readFileSync(process.argv[5])).data;
const timeline = JSON.parse(fs.readFileSync(process.argv[6])).data.events;
if (ended.status !== "closed") throw new Error("Visit did not close");
if (declined.status !== "closed" || declined.closeReason !== "declined") throw new Error("Reverse invitation was not declined");
if (care.careState !== null || !care.publicCare || !care.familiarity) throw new Error("Friend care privacy or familiarity failed");
for (const events of [alice, bob]) {
  if (!events.some((event) => event.type === "visit.activated")) throw new Error("missing activation event");
  if (!events.some((event) => event.type === "pet.care.updated")) throw new Error("missing care event");
  if (!events.some((event) => event.type === "visit.closed")) throw new Error("missing close event");
}
if (timeline.some((event) => event.type === "pet.care.updated")) throw new Error("care interaction leaked into timeline");
const closed = timeline.find((event) => event.type === "visit.closed" && event.aggregateID === ended.id);
if (closed?.payload?.interactionSummary?.counts?.feed !== 1) throw new Error("missing visit interaction summary");
if (closed?.payload?.interactionSummary?.letterAttached !== true) throw new Error("missing letter summary");
' "$scratch_dir/ended.json" "$scratch_dir/alice-events.json" "$scratch_dir/bob-events.json" \
  "$scratch_dir/care.json" "$scratch_dir/declined.json" "$scratch_dir/alice-timeline.json"

echo "Dual-profile model-free smoke passed: Alice $alice_account <-> Bob $bob_account"
