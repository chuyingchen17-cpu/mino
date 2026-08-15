#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
bundle_dir="$build_dir/Mino.app"
cache_dir="$project_dir/.cache"
configuration="${MINO_BUILD_CONFIGURATION:-debug}"

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "MINO_BUILD_CONFIGURATION must be 'debug' or 'release'" >&2
    exit 2
fi

mkdir -p "$cache_dir/clang" "$cache_dir/swiftpm" "$cache_dir/config" "$cache_dir/security"

env CLANG_MODULE_CACHE_PATH="$cache_dir/clang" swift build \
    --package-path "$project_dir" \
    --product Mino \
    --configuration "$configuration" \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"

mkdir -p "$bundle_dir/Contents/MacOS"
install -m 755 "$build_dir/$configuration/Mino" "$bundle_dir/Contents/MacOS/Mino"
cp "$project_dir/Support/Info.plist" "$bundle_dir/Contents/Info.plist"
plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null

echo "$bundle_dir"
