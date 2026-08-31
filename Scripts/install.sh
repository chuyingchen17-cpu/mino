#!/bin/zsh

set -euo pipefail

# One-click installer for the unsigned nightly macOS build published by CI.
# Designed to be piped:
#   curl -fsSL https://raw.githubusercontent.com/chuyingchen17-cpu/mino/main/Scripts/install.sh | zsh

MINO_REPO="${MINO_INSTALL_REPO:-chuyingchen17-cpu/mino}"
MINO_RELEASE="${MINO_INSTALL_RELEASE:-nightly}"
MINO_ASSET="${MINO_INSTALL_ASSET:-Mino-unsigned.zip}"
destination="${HOME}/Applications/Mino.app"
open_after_install=1
local_zip=""

usage() {
    cat <<'EOF'
Install the unsigned Mino macOS app from GitHub Releases.

  curl -fsSL https://raw.githubusercontent.com/chuyingchen17-cpu/mino/main/Scripts/install.sh | zsh
  Scripts/install.sh --zip .build/Mino-unsigned.zip
  curl ... | zsh -s -- --no-open

Environment:
  MINO_INSTALL_REPO      GitHub owner/name (default chuyingchen17-cpu/mino)
  MINO_INSTALL_RELEASE   Release tag (default nightly)
EOF
}

while (( $# )); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --no-open)
            open_after_install=0
            ;;
        --open)
            open_after_install=1
            ;;
        --zip)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "install.sh: --zip requires a path" >&2
                exit 2
            fi
            local_zip="$1"
            ;;
        *)
            echo "install.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Mino 只能安装在 macOS 上。" >&2
    exit 1
fi

os_major="${$(sw_vers -productVersion)%%.*}"
if (( os_major < 14 )); then
    echo "需要 macOS 14 或更高版本。" >&2
    exit 1
fi

tmp="$(mktemp -d /tmp/mino-install.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT INT TERM

# 返回值走 stdout，所以这个函数里的进度提示必须写到 stderr。
# 之前 "Downloading ..." 和 "SHA-256 ok" 用的是 stdout，调用处
# zip_path="$(download_release)" 会把三行一起捕获，ditto -x -k 拿到的
# 不是路径，一键安装每次都在解压这步失败。
download_release() {
    local zip_url="https://github.com/${MINO_REPO}/releases/download/${MINO_RELEASE}/${MINO_ASSET}"
    local sum_url="${zip_url}.sha256"
    local zip_path="$tmp/$MINO_ASSET"
    local sum_path="$tmp/$MINO_ASSET.sha256"

    echo "Downloading $zip_url" >&2
    if ! curl -fL --retry 3 --retry-delay 1 -o "$zip_path" "$zip_url"; then
        echo "没有找到可安装的包（${MINO_REPO} @ ${MINO_RELEASE}）。" >&2
        echo "CI 只在 main 测试通过后发布 nightly。也可从源码安装：" >&2
        echo "  git clone https://github.com/${MINO_REPO}.git" >&2
        echo "  cd mino && Scripts/install-app.sh --release --open" >&2
        exit 1
    fi

    if curl -fL --retry 3 --retry-delay 1 -o "$sum_path" "$sum_url"; then
        local expected actual
        expected="$(awk '{print $1}' "$sum_path")"
        actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
        if [[ -z "$expected" || "$expected" != "$actual" ]]; then
            echo "校验失败：下载的包与 SHA-256 不一致。" >&2
            exit 1
        fi
        echo "SHA-256 ok" >&2
    else
        echo "缺少 ${MINO_ASSET}.sha256，拒绝安装未校验的包。" >&2
        exit 1
    fi

    print -r -- "$zip_path"
}

extract_app() {
    local zip_path="$1"
    local extract_dir="$tmp/extracted"
    mkdir -p "$extract_dir"
    ditto -x -k "$zip_path" "$extract_dir"

    local app=""
    if [[ -d "$extract_dir/Mino-unsigned/Mino.app" ]]; then
        app="$extract_dir/Mino-unsigned/Mino.app"
    elif [[ -d "$extract_dir/Mino.app" ]]; then
        app="$extract_dir/Mino.app"
    else
        echo "压缩包里找不到 Mino.app。" >&2
        exit 1
    fi
    print -r -- "$app"
}

assert_compatible_binary() {
    local exe="$1/Contents/MacOS/Mino"
    if [[ ! -x "$exe" ]]; then
        echo "Mino.app 缺少可执行文件。" >&2
        exit 1
    fi
    local host="$(uname -m)"
    local archs
    archs="$(lipo -archs "$exe" 2>/dev/null || true)"
    if [[ -n "$archs" && "$archs" != *"$host"* ]]; then
        echo "这个包是 ${archs}，当前 Mac 是 ${host}。" >&2
        exit 1
    fi
    codesign --verify --deep --strict "$1"
}

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

zip_path=""
if [[ -n "$local_zip" ]]; then
    if [[ ! -f "$local_zip" ]]; then
        echo "找不到 $local_zip" >&2
        exit 1
    fi
    zip_path="${local_zip:A}"
else
    zip_path="$(download_release)"
fi

app="$(extract_app "$zip_path")"
assert_compatible_binary "$app"

mkdir -p "${destination:h}"
if [[ ! -w "${destination:h}" ]]; then
    echo "无法写入 ${destination:h}。未签名安装默认使用 ~/Applications，不使用 sudo。" >&2
    exit 1
fi

stop_bundle "$destination"
rm -rf "$destination"
ditto "$app" "$destination"
xattr -cr "$destination" 2>/dev/null || true
codesign --verify --deep --strict "$destination"

echo "Installed $destination"
echo "Mino 在菜单栏运行，没有 Dock 图标。"
echo "这是 CI 的 ad-hoc 包，不是 Developer ID 签名。同一份 app 再打开会保留登录；换一个构建需要重新登录。"
if (( open_after_install )); then
    open "$destination"
fi
