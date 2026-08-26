#!/bin/zsh

set -euo pipefail

# Install a locally built, ad-hoc signed Mino.app without an Apple Developer
# identity. Default destination is ~/Applications so the copy does not need
# sudo and is not treated as a notarized product.

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
source_bundle="$build_dir/Mino.app"
package_root="$build_dir/Mino-unsigned"
zip_path="$build_dir/Mino-unsigned.zip"
configuration="${MINO_BUILD_CONFIGURATION:-debug}"
destination="${HOME}/Applications/Mino.app"
open_after_install=0
skip_build=0
write_zip=0
do_install=1

usage() {
    cat <<'EOF'
Install a local ad-hoc Mino.app without an Apple Developer identity.

  Scripts/install-app.sh                 build and install to ~/Applications/Mino.app
  Scripts/install-app.sh --open          launch the menu-bar app after install
  Scripts/install-app.sh --release       optimized ad-hoc build
  Scripts/install-app.sh --zip           also write .build/Mino-unsigned.zip
  Scripts/install-app.sh --skip-build    reuse .build/Mino.app
  Scripts/install-app.sh --no-install    build (and optional zip) without copying
  Scripts/install-app.sh --destination PATH

Ad-hoc builds keep the login session in a file scoped to the current binary.
Rebuilding produces a new identity, so sign in again after each compile.
This is not a substitute for Developer ID distribution.
EOF
}

while (( $# )); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --open)
            open_after_install=1
            ;;
        --no-open)
            open_after_install=0
            ;;
        --skip-build)
            skip_build=1
            ;;
        --zip)
            write_zip=1
            ;;
        --no-install)
            do_install=0
            ;;
        --release)
            configuration=release
            ;;
        --destination)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Scripts/install-app.sh: --destination requires a path" >&2
                exit 2
            fi
            destination="$1"
            ;;
        *)
            echo "Scripts/install-app.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

destination="${destination/#\~/$HOME}"
destination="${destination:A}"

if (( write_zip )) && [[ ! -x /usr/bin/zip ]]; then
    echo "Required command is unavailable: zip" >&2
    exit 2
fi

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "MINO_BUILD_CONFIGURATION must be 'debug' or 'release'" >&2
    exit 2
fi

if (( ! skip_build )); then
    if [[ "$configuration" == "release" && -z "${MINO_CODE_SIGN_IDENTITY:-}" ]]; then
        export MINO_ALLOW_ADHOC_RELEASE=1
    fi
    MINO_BUILD_CONFIGURATION="$configuration" \
        "$project_dir/Scripts/build-app.sh" >/dev/null
fi

if [[ ! -d "$source_bundle" ]]; then
    echo "Missing $source_bundle. Run Scripts/build-app.sh first, or omit --skip-build." >&2
    exit 1
fi

codesign --verify --deep --strict "$source_bundle"

stop_bundle() {
    local bundle="$1"
    local exe="$bundle/Contents/MacOS/Mino"
    [[ -e "$exe" ]] || return 0

    local -a pids
    pids=("${(@f)$(pgrep -f "$exe" 2>/dev/null || true)}")
    pids=("${pids[@]:#}")
    (( $#pids )) || return 0

    echo "Stopping the running Mino at $bundle"
    kill "${pids[@]}" 2>/dev/null || true
    local i
    for i in {1..25}; do
        pgrep -f "$exe" >/dev/null 2>&1 || return 0
        sleep 0.1
    done
    kill -9 "${pids[@]}" 2>/dev/null || true
}

clear_quarantine() {
    xattr -cr "$1" 2>/dev/null || true
}

write_unsigned_package() {
    rm -rf "$package_root" "$zip_path"
    mkdir -p "$package_root"
    ditto "$source_bundle" "$package_root/Mino.app"
    clear_quarantine "$package_root/Mino.app"

    cat > "$package_root/README.txt" <<'EOF'
Mino 未签名本机包

这个包使用 ad-hoc 签名，不需要 Apple 开发者账号。
它不能作为正式分发版本；从网盘或隔空投送打开时，系统可能提示无法验证开发者。

安装
1. 保持本文件夹完整，不要只拷贝 Mino.app。
2. 双击 Install-Mino.command。
3. 若被拦截：按住 Control 单击该文件 → 打开。
4. 安装位置：~/Applications/Mino.app

终端：

  xattr -cr .
  ./Install-Mino.command

Mino 在菜单栏运行，没有 Dock 图标。
同一份 app 再打开会保留登录；重新编译后的新包需要重新登录。
EOF

    cat > "$package_root/Install-Mino.command" <<'EOF'
#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
if [[ ! -d "./Mino.app" ]]; then
    osascript -e 'display alert "找不到 Mino.app" message "请把整个文件夹保持在一起后再运行安装。"' >/dev/null
    exit 1
fi

destination="${HOME}/Applications/Mino.app"
mkdir -p "${HOME}/Applications"

xattr -cr "./Mino.app" 2>/dev/null || true
xattr -cr "./Install-Mino.command" 2>/dev/null || true

exe="$destination/Contents/MacOS/Mino"
if [[ -e "$exe" ]]; then
    pids=("${(@f)$(pgrep -f "$exe" 2>/dev/null || true)}")
    pids=("${pids[@]:#}")
    if (( $#pids )); then
        kill "${pids[@]}" 2>/dev/null || true
        sleep 0.4
        kill -9 "${pids[@]}" 2>/dev/null || true
    fi
fi

rm -rf "$destination"
ditto "./Mino.app" "$destination"
xattr -cr "$destination" 2>/dev/null || true
open "$destination"

osascript -e 'display notification "已安装到「应用程序」。Mino 会出现在菜单栏，没有 Dock 图标。" with title "Mino"' >/dev/null
EOF
    chmod 755 "$package_root/Install-Mino.command"

    (
        cd "$build_dir"
        rm -f Mino-unsigned.zip
        # zip -X skips macOS xattrs. ditto -c -k would serialize provenance
        # attributes as ._ sidecars next to every PNG.
        /usr/bin/zip -r -X -q Mino-unsigned.zip Mino-unsigned \
            -x '*.DS_Store' -x '*/._*' -x '*._*'
    )
    echo "$zip_path"
}

if (( write_zip )); then
    write_unsigned_package
fi

if (( do_install )); then
    mkdir -p "${destination:h}"
    if [[ ! -w "${destination:h}" ]]; then
        echo "Cannot write to ${destination:h}." >&2
        echo "The unsigned installer defaults to ~/Applications and does not use sudo." >&2
        exit 1
    fi
    stop_bundle "$destination"
    rm -rf "$destination"
    ditto "$source_bundle" "$destination"
    clear_quarantine "$destination"
    codesign --verify --deep --strict "$destination"

    echo "Installed $destination"
    echo "Launch:  open \"$destination\""
    echo "Mino stays in the menu bar; it does not show a Dock icon."
    echo "Ad-hoc login is kept for this binary only. Sign in again after rebuilding."

    if (( open_after_install )); then
        open "$destination"
    fi
fi
