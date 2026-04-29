#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Scribeosaur.xcodeproj"
SCHEME_NAME="Scribeosaur"
APP_NAME="Scribeosaur"

BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORTED_APP_PATH="$BUILD_ROOT/$APP_NAME.app"
DMG_STAGE_PATH="$BUILD_ROOT/dmg"
TOOLS_PATH="$BUILD_ROOT/tools"
PKG_PATH="$DIST_DIR/$APP_NAME-Installer.pkg"
DMG_PATH="$DIST_DIR/$APP_NAME-Installer.dmg"
MODEL_SEED_ID="${MODEL_SEED_ID:-gemma-e4b-4bit-local}"
MODEL_MANIFEST_PATH="${MODEL_MANIFEST_PATH:-$ROOT_DIR/Scribeosaur/Resources/AIModels/gemma-e4b-4bit.json}"
AI_RUNTIME_SEED_PATH="${AI_RUNTIME_SEED_PATH:-}"

FFMPEG_URL="https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip"
UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Missing required environment variable: $name" >&2
        exit 1
    fi
}

prepare_directories() {
    rm -rf "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT" "$DIST_DIR" "$TOOLS_PATH"
}

verify_model_manifest() {
    "$ROOT_DIR/scripts/generate_model_manifest.swift" --check "$MODEL_MANIFEST_PATH"
}

copy_or_download() {
    local source="$1"
    local destination="$2"

    if printf '%s' "$source" | grep -Eq '^https?://'; then
        curl --fail --location --silent --show-error "$source" --output "$destination"
    else
        ditto "$source" "$destination"
    fi
}

prepare_ffmpeg() {
    local source="${FFMPEG_SOURCE:-$FFMPEG_URL}"
    local download_path="$TOOLS_PATH/ffmpeg-source"
    local unzip_path="$TOOLS_PATH/ffmpeg-unzip"
    local binary_path="$TOOLS_PATH/ffmpeg"

    rm -rf "$download_path" "$unzip_path" "$binary_path"
    mkdir -p "$unzip_path"

    copy_or_download "$source" "$download_path"

    if file "$download_path" | grep -qi 'zip archive'; then
        ditto -xk "$download_path" "$unzip_path"
        local extracted
        extracted="$(find "$unzip_path" -type f -name ffmpeg | head -n 1)"
        if [ -z "$extracted" ]; then
            echo "Failed to locate ffmpeg in downloaded archive." >&2
            exit 1
        fi
        ditto "$extracted" "$binary_path"
    else
        ditto "$download_path" "$binary_path"
    fi

    chmod 755 "$binary_path"
}

prepare_ytdlp() {
    local source="${YTDLP_SOURCE:-$YTDLP_URL}"
    local binary_path="$TOOLS_PATH/yt-dlp"

    rm -f "$binary_path"
    copy_or_download "$source" "$binary_path"
    chmod 755 "$binary_path"
}

prepare_deno() {
    local source="${DENO_SOURCE:-$DENO_URL}"
    local download_path="$TOOLS_PATH/deno-source"
    local unzip_path="$TOOLS_PATH/deno-unzip"
    local binary_path="$TOOLS_PATH/deno"

    rm -rf "$download_path" "$unzip_path" "$binary_path"
    mkdir -p "$unzip_path"

    copy_or_download "$source" "$download_path"

    if file "$download_path" | grep -qi 'zip archive'; then
        ditto -xk "$download_path" "$unzip_path"
        local extracted
        extracted="$(find "$unzip_path" -type f -name deno | head -n 1)"
        if [ -z "$extracted" ]; then
            echo "Failed to locate deno in downloaded archive." >&2
            exit 1
        fi
        ditto "$extracted" "$binary_path"
    else
        ditto "$download_path" "$binary_path"
    fi

    chmod 755 "$binary_path"
}

prepare_uv() {
    local source="${UV_SOURCE:-$UV_URL}"
    local download_path="$TOOLS_PATH/uv-source"
    local extract_path="$TOOLS_PATH/uv-extract"
    local binary_path="$TOOLS_PATH/uv"

    rm -rf "$download_path" "$extract_path" "$binary_path"
    mkdir -p "$extract_path"

    copy_or_download "$source" "$download_path"

    if file "$download_path" | grep -Eqi 'gzip compressed|tar archive'; then
        tar -xzf "$download_path" -C "$extract_path"
        local extracted
        extracted="$(find "$extract_path" -type f -name uv | head -n 1)"
        if [ -z "$extracted" ]; then
            echo "Failed to locate uv in downloaded archive." >&2
            exit 1
        fi
        ditto "$extracted" "$binary_path"
    else
        ditto "$download_path" "$binary_path"
    fi

    chmod 755 "$binary_path"
}

archive_app() {
    xcodegen generate >/dev/null

    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME_NAME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_PATH" \
        archive
}

export_app_bundle() {
    local archived_app="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

    if [ ! -d "$archived_app" ]; then
        echo "Archived app not found at $archived_app" >&2
        exit 1
    fi

    rm -rf "$EXPORTED_APP_PATH"
    ditto "$archived_app" "$EXPORTED_APP_PATH"
}

stage_bundle_resources() {
    local resources_path="$EXPORTED_APP_PATH/Contents/Resources"
    local binaries_path="$resources_path/Binaries"

    mkdir -p "$binaries_path"
    ditto "$TOOLS_PATH/ffmpeg" "$binaries_path/ffmpeg"
    ditto "$TOOLS_PATH/yt-dlp" "$binaries_path/yt-dlp"
    ditto "$TOOLS_PATH/deno" "$binaries_path/deno"
    ditto "$TOOLS_PATH/uv" "$binaries_path/uv"
    chmod 755 "$binaries_path/ffmpeg" "$binaries_path/yt-dlp" "$binaries_path/deno" "$binaries_path/uv"

    if [ -n "${MODEL_SEED_PATH:-}" ]; then
        local model_seed_destination="$resources_path/ModelSeed/$MODEL_SEED_ID"
        rm -rf "$model_seed_destination"
        mkdir -p "$(dirname "$model_seed_destination")"
        ditto "$MODEL_SEED_PATH" "$model_seed_destination"
    fi

    if [ -n "$AI_RUNTIME_SEED_PATH" ]; then
        local runtime_seed_destination="$resources_path/AIRuntimeSeed"
        rm -rf "$runtime_seed_destination"
        ditto "$AI_RUNTIME_SEED_PATH" "$runtime_seed_destination"
    fi
}

sign_bundle() {
    xattr -cr "$EXPORTED_APP_PATH"

    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP" \
        "$EXPORTED_APP_PATH/Contents/Resources/Binaries/ffmpeg"
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP" \
        "$EXPORTED_APP_PATH/Contents/Resources/Binaries/yt-dlp"
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP" \
        "$EXPORTED_APP_PATH/Contents/Resources/Binaries/deno"
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP" \
        "$EXPORTED_APP_PATH/Contents/Resources/Binaries/uv"

    if [ -n "$AI_RUNTIME_SEED_PATH" ]; then
        while IFS= read -r executable; do
            codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP" "$executable"
        done < <(find "$EXPORTED_APP_PATH/Contents/Resources/AIRuntimeSeed" -type f -perm -u+x)
    fi

    codesign --force --deep --timestamp --options runtime \
        --preserve-metadata=entitlements,requirements,flags \
        --sign "$DEVELOPER_ID_APP" \
        "$EXPORTED_APP_PATH"

    codesign --verify --deep --strict "$EXPORTED_APP_PATH"
}

build_pkg() {
    rm -f "$PKG_PATH"
    productbuild \
        --component "$EXPORTED_APP_PATH" /Applications \
        --sign "$DEVELOPER_ID_INSTALLER" \
        "$PKG_PATH"
}

notarize_if_configured() {
    local artifact="$1"

    if [ -z "${NOTARY_PROFILE:-}" ]; then
        return
    fi

    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$artifact"
}

build_dmg() {
    rm -rf "$DMG_STAGE_PATH"
    mkdir -p "$DMG_STAGE_PATH"

    cp "$PKG_PATH" "$DMG_STAGE_PATH/"

    cat >"$DMG_STAGE_PATH/Install Scribeosaur.txt" <<'EOF'
Open the installer package and follow the prompts.

The installed app includes:
- bundled ffmpeg
- bundled yt-dlp
- bundled deno
- bundled uv
- optional offline model seed if one was supplied at build time
- optional offline AI runtime seed if one was supplied at build time
EOF

    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME Installer" \
        -srcfolder "$DMG_STAGE_PATH" \
        -format UDZO \
        "$DMG_PATH"
}

main() {
    require_command curl
    require_command codesign
    require_command ditto
    require_command hdiutil
    require_command productbuild
    require_command swift
    require_command tar
    require_command xcodebuild
    require_command xcodegen

    require_env DEVELOPER_ID_APP
    require_env DEVELOPER_ID_INSTALLER

    prepare_directories
    verify_model_manifest
    prepare_ffmpeg
    prepare_ytdlp
    prepare_deno
    prepare_uv
    archive_app
    export_app_bundle
    stage_bundle_resources
    sign_bundle
    build_pkg
    notarize_if_configured "$PKG_PATH"
    build_dmg
    notarize_if_configured "$DMG_PATH"

    echo "Created:"
    echo "  $PKG_PATH"
    echo "  $DMG_PATH"
}

main "$@"
