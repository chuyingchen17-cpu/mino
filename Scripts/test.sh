#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
cache_dir="${MINO_CACHE_DIR:-$project_dir/.cache}"

if (( ! $+commands[npm] )); then
    echo "Required command is unavailable: npm" >&2
    exit 2
fi

zsh -n "$project_dir/Scripts/install.sh"
zsh -n "$project_dir/Scripts/install-app.sh"
zsh -n "$project_dir/Scripts/build-app.sh"

if [[ ! -d "$project_dir/Backend/node_modules" ]]; then
    npm --prefix "$project_dir/Backend" ci
fi

mkdir -p "$cache_dir/clang" "$cache_dir/swiftpm" "$cache_dir/config" "$cache_dir/security"

env CLANG_MODULE_CACHE_PATH="$cache_dir/clang" swift test \
    --package-path "$project_dir" \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"

npm --prefix "$project_dir/Backend" run typecheck
npm --prefix "$project_dir/Backend" test
npm --prefix "$project_dir/Backend" run openapi
npm --prefix "$project_dir/Backend" run deploy:dry-run
