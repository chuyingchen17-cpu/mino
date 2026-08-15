#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
cache_dir="$project_dir/.cache"

mkdir -p "$cache_dir/clang" "$cache_dir/swiftpm" "$cache_dir/config" "$cache_dir/security"

env CLANG_MODULE_CACHE_PATH="$cache_dir/clang" swift test \
    --package-path "$project_dir" \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"
