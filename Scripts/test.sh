#!/bin/zsh

set -euo pipefail

root_dir="${0:A:h:h}"
macos_dir="$root_dir/apps/macos"
worker_dir="$root_dir/apps/worker"
cache_dir="${MINO_CACHE_DIR:-$root_dir/.cache}"

if (( ! $+commands[npm] )); then
    echo "Required command is unavailable: npm" >&2
    exit 2
fi

zsh -n "$root_dir/Scripts/install.sh"
zsh -n "$root_dir/Scripts/install-app.sh"
zsh -n "$root_dir/Scripts/build-app.sh"

if [[ ! -d "$worker_dir/node_modules" ]]; then
    npm --prefix "$worker_dir" ci
fi

mkdir -p "$cache_dir/clang" "$cache_dir/swiftpm" "$cache_dir/config" "$cache_dir/security"

env CLANG_MODULE_CACHE_PATH="$cache_dir/clang" swift test \
    --package-path "$macos_dir" \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"

npm --prefix "$worker_dir" run typecheck
npm --prefix "$worker_dir" test
npm --prefix "$worker_dir" run openapi
npm --prefix "$worker_dir" run deploy:dry-run
