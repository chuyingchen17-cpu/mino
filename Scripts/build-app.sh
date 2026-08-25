#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
bundle_dir="$build_dir/Mino.app"
staging_dir="$build_dir/Mino.app.staging"
cache_dir="${MINO_CACHE_DIR:-$project_dir/.cache}"
configuration="${MINO_BUILD_CONFIGURATION:-debug}"
marketing_version="${MINO_MARKETING_VERSION:-0.1.0}"
build_number="${MINO_BUILD_NUMBER:-1}"
backend_mode="${MINO_BACKEND_MODE:-remote}"
api_base_url="${MINO_API_BASE_URL:-https://api.mino.pet}"
api_version="${MINO_API_VERSION:-v1}"
request_timeout="${MINO_REQUEST_TIMEOUT:-10}"
app_iconset_dir="$build_dir/Mino.iconset"

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "MINO_BUILD_CONFIGURATION must be 'debug' or 'release'" >&2
    exit 2
fi

if [[ "$configuration" == "release" \
    && -z "${MINO_CODE_SIGN_IDENTITY:-}" \
    && "${MINO_ALLOW_ADHOC_RELEASE:-0}" != "1" ]]; then
    echo "Release bundles require MINO_CODE_SIGN_IDENTITY for a stable Keychain identity." >&2
    echo "CI-only validation may set MINO_ALLOW_ADHOC_RELEASE=1; do not distribute that artifact." >&2
    exit 2
fi

if [[ "$backend_mode" != "offline" && "$backend_mode" != "remote" ]]; then
    echo "MINO_BACKEND_MODE must be 'offline' or 'remote'" >&2
    exit 2
fi

if [[ "$backend_mode" == "remote" && -z "$api_base_url" ]]; then
    echo "MINO_API_BASE_URL is required for a remote backend build" >&2
    exit 2
fi

if [[ -z "$api_version" || "$api_version" == *[^A-Za-z0-9_-]* ]]; then
    echo "MINO_API_VERSION may contain only letters, numbers, '-' and '_'" >&2
    exit 2
fi

if [[ "$request_timeout" != <-> ]] || (( request_timeout < 1 || request_timeout > 60 )); then
    echo "MINO_REQUEST_TIMEOUT must be an integer from 1 through 60" >&2
    exit 2
fi

if [[ "$backend_mode" == "remote" \
    && "$api_base_url" != https://* \
    && "$api_base_url" != http://localhost* \
    && "$api_base_url" != http://127.0.0.1* \
    && "$api_base_url" != http://\[::1\]* ]]; then
    echo "Remote backends must use HTTPS; HTTP is allowed only for local development" >&2
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

rm -rf "$staging_dir"
mkdir -p "$staging_dir/Contents/MacOS" "$staging_dir/Contents/Resources"
install -m 755 "$build_dir/$configuration/Mino" "$staging_dir/Contents/MacOS/Mino"
presentation_resource_bundle="$build_dir/$configuration/Mino_MinoPresentation.bundle"
if [[ ! -d "$presentation_resource_bundle" ]]; then
    echo "Missing MinoPresentation frame resource bundle: $presentation_resource_bundle" >&2
    exit 2
fi
# Copy only the current frame tree so stale resources from an incremental
# pre-frame build can never resurrect retired sprites. The product catalog
# explicitly prefers Contents/Resources/PetFrames; placing a SwiftPM bundle at
# the .app root creates an unsealed macOS bundle and fails strict code signing.
if [[ ! -d "$presentation_resource_bundle/PetFrames" ]]; then
    echo "Missing packaged PetFrames directory" >&2
    exit 2
fi
cp -R "$presentation_resource_bundle/PetFrames" \
    "$staging_dir/Contents/Resources/PetFrames"
rm -rf "$app_iconset_dir"
mkdir -p "$app_iconset_dir"
/usr/bin/xcrun swift "$project_dir/Scripts/generate-app-icon.swift" "$app_iconset_dir"
/usr/bin/iconutil --convert icns \
    --output "$staging_dir/Contents/Resources/Mino.icns" \
    "$app_iconset_dir"
rm -rf "$app_iconset_dir"
cp "$project_dir/Support/Info.plist" "$staging_dir/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$marketing_version" "$staging_dir/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$staging_dir/Contents/Info.plist"
plutil -replace MinoBackendMode -string "$backend_mode" "$staging_dir/Contents/Info.plist"
plutil -replace MinoAPIBaseURL -string "$api_base_url" "$staging_dir/Contents/Info.plist"
plutil -replace MinoAPIVersion -string "$api_version" "$staging_dir/Contents/Info.plist"
plutil -replace MinoRequestTimeout -integer "$request_timeout" "$staging_dir/Contents/Info.plist"
plutil -lint "$staging_dir/Contents/Info.plist" >/dev/null

if [[ -n "${MINO_CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force \
        --options runtime \
        --entitlements "$project_dir/Support/Mino.entitlements" \
        --sign "$MINO_CODE_SIGN_IDENTITY" \
        "$staging_dir"
else
    if [[ "$configuration" == "debug" ]]; then
        echo "Warning: ad-hoc Debug uses a build-scoped encrypted session store." >&2
        echo "Set MINO_CODE_SIGN_IDENTITY to preserve the login session across rebuilds." >&2
    fi
    # SwiftPM only linker-signs the executable. Sign the assembled bundle so
    # macOS binds Info.plist and resources to the application identity too.
    codesign --force --sign - "$staging_dir"
fi
codesign --verify --deep --strict "$staging_dir"

rm -rf "$bundle_dir"
mv "$staging_dir" "$bundle_dir"

echo "$bundle_dir"
