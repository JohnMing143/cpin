#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="release"
UNIVERSAL=false
for option in "$@"; do
    case "$option" in
        --debug) CONFIGURATION="debug" ;;
        --universal) UNIVERSAL=true ;;
        *) printf 'Usage: %s [--debug] [--universal]\n' "$0" >&2; exit 2 ;;
    esac
done

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" -c "$CONFIGURATION")

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpin-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
APP="$STAGING_DIRECTORY/Cpin.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if $UNIVERSAL; then
    BINARIES=()
    for architecture in arm64 x86_64; do
        ARCH_OPTIONS=(--scratch-path "$ROOT/.build/$architecture" --triple "$architecture-apple-macosx13.0")
        swift build "${SWIFT_OPTIONS[@]}" "${ARCH_OPTIONS[@]}" --product Cpin
        BINARY_DIRECTORY="$(swift build "${SWIFT_OPTIONS[@]}" "${ARCH_OPTIONS[@]}" --show-bin-path)"
        BINARIES+=("$BINARY_DIRECTORY/Cpin")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Cpin"
    lipo "$APP/Contents/MacOS/Cpin" -verify_arch arm64 x86_64
    # Keep the running development app untouched when preparing a shared build.
    OUTPUT_DIRECTORY="$ROOT/build/universal"
else
    swift build "${SWIFT_OPTIONS[@]}" --product Cpin
    BINARY_DIRECTORY="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
    cp "$BINARY_DIRECTORY/Cpin" "$APP/Contents/MacOS/Cpin"
    OUTPUT_DIRECTORY="$ROOT/build"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$ROOT/scripts/make-icon.swift" "$APP/Contents/Resources/Cpin.icns"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$OUTPUT_DIRECTORY"
# Keep a clean, signed archive even when the workspace lives in a synced folder.
ditto --noextattr --norsrc -c -k --keepParent "$APP" "$OUTPUT_DIRECTORY/Cpin.zip"
ditto "$APP" "$OUTPUT_DIRECTORY/Cpin.app"
printf '\nBuilt %s\nArchive: %s\nRun: open "%s"\n' "$OUTPUT_DIRECTORY/Cpin.app" "$OUTPUT_DIRECTORY/Cpin.zip" "$OUTPUT_DIRECTORY/Cpin.app"
