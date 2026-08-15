#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
bundle_dir="$build_dir/MinoPoC.app"
cache_dir="$project_dir/.cache"

mkdir -p "$cache_dir/clang" "$cache_dir/swiftpm" "$cache_dir/config" "$cache_dir/security"

env CLANG_MODULE_CACHE_PATH="$cache_dir/clang" swift build \
    --package-path "$project_dir" \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"

mkdir -p "$bundle_dir/Contents/MacOS"
cp "$build_dir/arm64-apple-macosx/debug/MinoPoC" "$bundle_dir/Contents/MacOS/MinoPoC"
cp "$project_dir/Support/Info.plist" "$bundle_dir/Contents/Info.plist"

echo "$bundle_dir"

