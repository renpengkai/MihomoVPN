#!/usr/bin/env bash
# 构建 release 二进制并组装成 dist/MihomoVPN.app + zip。
#   VERSION           CFBundleShortVersionString, 默认 0.1.0
#   BUILD             CFBundleVersion, 默认 1
#   ARCH              arm64 / x86_64, 默认 arm64
#   BUNDLE_CORE       0 = 不内置内核 (默认, 体积最小), 1 = 内置最新 Mihomo
#   MIHOMO_VERSION    内置内核版本, 如 1.19.32; 默认取 MetaCubeX/mihomo 最新正式版
#   GITHUB_TOKEN      可选, 查询最新版本时使用
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
ARCH="${ARCH:-arm64}"
BUNDLE_CORE="${BUNDLE_CORE:-0}"
NAME="MihomoVPN"
HELPER="mvpnhelper"
CORE="mihomo"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

DIST="$ROOT/dist"
APP="$DIST/$NAME.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
    cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ROOT/Packaging/AppIcon.png" ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    AT='@'
    for SPEC in \
        "16:icon_16x16.png" "32:icon_16x16${AT}2x.png" \
        "32:icon_32x32.png" "64:icon_32x32${AT}2x.png" \
        "128:icon_128x128.png" "256:icon_128x128${AT}2x.png" \
        "256:icon_256x256.png" "512:icon_256x256${AT}2x.png" \
        "512:icon_512x512.png" "1024:icon_512x512${AT}2x.png"
    do
        SIZE="${SPEC%%:*}"
        NAME_PNG="${SPEC#*:}"
        sips -z "$SIZE" "$SIZE" "$ROOT/Packaging/AppIcon.png" --out "$ICONSET/$NAME_PNG" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
for BIN in "$NAME" "$HELPER"; do
    OUT="$APP/Contents/MacOS/$BIN"
    cp "$BIN_DIR/$BIN" "$OUT"
    strip -S -x "$OUT"
    # SwiftPM 把 LC_BUILD_VERSION 的 sdk 写成部署目标, 系统会按旧 SDK 兼容模式运行并禁用液态玻璃
    vtool -set-build-version macos 13.0 "$SDK_VERSION" -replace -output "$OUT.tmp" "$OUT"
    mv "$OUT.tmp" "$OUT"
    chmod +x "$OUT"
done

CORE_VERSION=""
if [[ "$BUNDLE_CORE" == "1" ]]; then
    case "$ARCH" in
        arm64) CORE_ARCH="arm64" ;;
        x86_64) CORE_ARCH="amd64" ;;
        *) echo "unsupported ARCH: $ARCH" >&2; exit 1 ;;
    esac
    CORE_VERSION="${MIHOMO_VERSION:-}"
    if [[ -z "$CORE_VERSION" ]]; then
        AUTH=()
        [[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
        CORE_VERSION="$(curl -fsSL ${AUTH[@]+"${AUTH[@]}"} \
            https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
            | plutil -extract tag_name raw -o - -)"
    fi
    CORE_VERSION="${CORE_VERSION#v}"
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    GZ="mihomo-darwin-$CORE_ARCH-v$CORE_VERSION.gz"
    echo "== bundling $GZ =="
    curl -fsSL -o "$WORK/core.gz" \
        "https://github.com/MetaCubeX/mihomo/releases/download/v$CORE_VERSION/$GZ"
    OUT="$APP/Contents/MacOS/$CORE"
    gzip -dc "$WORK/core.gz" > "$OUT"
    chmod +x "$OUT"
    "$OUT" -v
fi

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s/__CORE_VERSION__/$CORE_VERSION/" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

for BIN in "$HELPER" "$CORE"; do
    if [[ -f "$APP/Contents/MacOS/$BIN" ]]; then
        codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/$BIN"
    fi
done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="$DIST/$NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== size =="
du -sh "$APP"
ls -l "$APP/Contents/MacOS/" "$ZIP"
vtool -show-build "$APP/Contents/MacOS/$NAME"
