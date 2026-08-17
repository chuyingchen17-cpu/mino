#!/bin/zsh

set -euo pipefail
setopt NO_BG_NICE

project_dir="${0:A:h:h}"
api_base_url="${MINO_API_BASE_URL:-http://127.0.0.1:8080}"
api_version="${MINO_API_VERSION:-v1}"
configuration="${MINO_BUILD_CONFIGURATION:-debug}"
database_url="${MINO_DEV_DATABASE_URL:-postgres://mino:mino_dev_only@127.0.0.1:5432/mino}"
cache_dir="$project_dir/.cache"

for command_name in curl swift npm node ditto plutil codesign; do
    if (( ! $+commands[$command_name] )); then
        echo "Required command is unavailable: $command_name" >&2
        exit 2
    fi
done

if [[ "$configuration" != "debug" ]]; then
    echo "Dual-client profiles are intended for a debug build." >&2
    echo "Set MINO_BUILD_CONFIGURATION=debug or omit it." >&2
    exit 2
fi

if [[ ! "$api_base_url" =~ '^http://(127\.0\.0\.1|localhost):[0-9]+$' ]]; then
    echo "Dual-client MVP requires a loopback HTTP API URL with an explicit port." >&2
    exit 2
fi
if [[ ! "$database_url" =~ '^postgres(ql)?://[^@/]+@(127\.0\.0\.1|localhost):[0-9]+/[^/?#]+$' ]]; then
    echo "MINO_DEV_DATABASE_URL must point to a loopback development database." >&2
    exit 2
fi

backend_port="${api_base_url##*:}"
backend_pid=""
alice_pid=""
bob_pid=""

stop_clients() {
    if [[ -n "$alice_pid" ]]; then
        kill "$alice_pid" 2>/dev/null || true
    fi
    if [[ -n "$bob_pid" ]]; then
        kill "$bob_pid" 2>/dev/null || true
    fi
    if [[ -n "$backend_pid" ]]; then
        kill "$backend_pid" 2>/dev/null || true
    fi
}

trap stop_clients EXIT INT TERM

start_backend_if_needed() {
    if curl --fail --silent "$api_base_url/$api_version/health" >/dev/null 2>&1; then
        return
    fi

    if (( ! $+commands[docker] )); then
        echo "Backend is offline and Docker is unavailable." >&2
        echo "Install/start Docker, or start Backend manually at $api_base_url." >&2
        exit 1
    fi

    docker compose --file "$project_dir/Backend/compose.yaml" up --detach postgres

    if [[ ! -d "$project_dir/Backend/node_modules" ]]; then
        npm --prefix "$project_dir/Backend" ci
    fi

    local migration_ready=false
    for _ in {1..30}; do
        if env \
            NODE_ENV=development \
            DATABASE_URL="$database_url" \
            npm --prefix "$project_dir/Backend" run db:migrate >/dev/null 2>&1; then
            migration_ready=true
            break
        fi
        sleep 1
    done
    if [[ "$migration_ready" != true ]]; then
        echo "PostgreSQL did not become ready for migrations." >&2
        exit 1
    fi

    npm --prefix "$project_dir/Backend" run build
    env \
        NODE_ENV=development \
        HOST=127.0.0.1 \
        PORT="$backend_port" \
        DATABASE_URL="$database_url" \
        DEV_BOOTSTRAP_ENABLED=true \
        node "$project_dir/Backend/dist/src/server.js" &
    backend_pid=$!

    local backend_ready=false
    for _ in {1..30}; do
        if curl --fail --silent "$api_base_url/$api_version/health" >/dev/null 2>&1; then
            backend_ready=true
            break
        fi
        sleep 1
    done
    if [[ "$backend_ready" != true ]]; then
        echo "Mino backend failed to become healthy at $api_base_url." >&2
        exit 1
    fi
}

start_backend_if_needed

if ! curl --fail --silent --show-error \
    --request POST \
    --header 'Content-Type: application/json' \
    --data '{"profile":"alice"}' \
    "$api_base_url/$api_version/dev/bootstrap" >/dev/null; then
    echo "The backend is healthy but development bootstrap is unavailable." >&2
    echo "Stop the existing server or restart it with DEV_BOOTSTRAP_ENABLED=true." >&2
    exit 1
fi

mkdir -p \
    "$cache_dir/clang" \
    "$cache_dir/swiftpm" \
    "$cache_dir/config" \
    "$cache_dir/security"

env \
    CLANG_MODULE_CACHE_PATH="$cache_dir/clang" \
    MINO_BUILD_CONFIGURATION="$configuration" \
    MINO_BACKEND_MODE=remote \
    MINO_API_BASE_URL="$api_base_url" \
    MINO_API_VERSION="$api_version" \
    "$project_dir/Scripts/build-app.sh" >/dev/null

base_bundle="$project_dir/.build/Mino.app"
dual_bundle_root="$project_dir/.build/dual-clients"
rm -rf "$dual_bundle_root"
mkdir -p "$dual_bundle_root"

prepare_profile_bundle() {
    local profile="$1"
    local display_name="$2"
    local bundle_identifier="$3"
    local profile_bundle="$dual_bundle_root/Mino-$profile.app"

    ditto "$base_bundle" "$profile_bundle"
    plutil -replace CFBundleIdentifier -string "$bundle_identifier" \
        "$profile_bundle/Contents/Info.plist"
    plutil -replace CFBundleName -string "$display_name" \
        "$profile_bundle/Contents/Info.plist"
    plutil -replace MinoClientProfile -string "$profile" \
        "$profile_bundle/Contents/Info.plist"
    codesign --force --sign - "$profile_bundle" >/dev/null 2>&1
    codesign --verify --deep --strict "$profile_bundle"

    print -r -- "$profile_bundle"
}

alice_bundle="$(prepare_profile_bundle alice 'Mino Alice' 'com.mino.app.debug.alice')"
bob_bundle="$(prepare_profile_bundle bob 'Mino Bob' 'com.mino.app.debug.bob')"
alice_executable="$alice_bundle/Contents/MacOS/Mino"
bob_executable="$bob_bundle/Contents/MacOS/Mino"

env \
    MINO_CLIENT_PROFILE=alice \
    MINO_BACKEND_MODE=remote \
    MINO_API_BASE_URL="$api_base_url" \
    MINO_API_VERSION="$api_version" \
    "$alice_executable" &
alice_pid=$!

env \
    MINO_CLIENT_PROFILE=bob \
    MINO_BACKEND_MODE=remote \
    MINO_API_BASE_URL="$api_base_url" \
    MINO_API_VERSION="$api_version" \
    "$bob_executable" &
bob_pid=$!

echo "Alice client PID: $alice_pid"
echo "Bob client PID:   $bob_pid"
echo "Press Control-C to stop both clients."

wait "$alice_pid" "$bob_pid"
