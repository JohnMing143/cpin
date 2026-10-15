#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--skip-build]\n' "$0" >&2
    exit 2
fi
case "${1:-}" in
    "") "$ROOT/scripts/build.sh" --universal ;;
    --skip-build) ;;
    *) printf 'Usage: %s [--skip-build]\n' "$0" >&2; exit 2 ;;
esac

ARCHIVE="$ROOT/build/universal/Cpin.zip"
if [[ ! -f "$ARCHIVE" ]]; then
    printf 'Missing universal build. Run ./scripts/build.sh --universal first.\n' >&2
    exit 1
fi

DMG_WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpin-dmg.XXXXXX")"
DMG_MOUNT_POINT="$DMG_WORK_DIRECTORY/mounted"
DMG_MOUNTED=false
cleanup() {
    # attach may mount the volume before reporting a later error.
    if $DMG_MOUNTED || { [[ -d "$DMG_MOUNT_POINT" ]] &&
        [[ "$(stat -f %d "$DMG_MOUNT_POINT")" != "$(stat -f %d "$DMG_WORK_DIRECTORY")" ]]; }; then
        if ! hdiutil detach "$DMG_MOUNT_POINT" -quiet; then
            printf 'Could not unmount %s; temporary files were kept.\n' "$DMG_MOUNT_POINT" >&2
            return
        fi
    fi
    rm -rf "$DMG_WORK_DIRECTORY"
}
trap cleanup EXIT

PAYLOAD="$DMG_WORK_DIRECTORY/payload"
mkdir -p "$PAYLOAD"
# Extract the metadata-free archive instead of copying the workspace bundle.
ditto -x -k "$ARCHIVE" "$PAYLOAD"
APP="$PAYLOAD/Cpin.app"
codesign --verify --deep --strict --all-architectures "$APP"
lipo "$APP/Contents/MacOS/Cpin" -verify_arch arm64 x86_64
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Unsupported release version: %s\n' "$VERSION" >&2
    exit 1
fi
ln -s /Applications "$PAYLOAD/Applications"
cp "$ROOT/Resources/DMG-使用说明.txt" "$PAYLOAD/使用说明.txt"

DMG_NAME="Cpin-$VERSION-universal.dmg"
TEMP_DMG="$DMG_WORK_DIRECTORY/$DMG_NAME"
hdiutil create -volname "Cpin $VERSION" -srcfolder "$PAYLOAD" \
    -format UDZO -fs HFS+ -imagekey zlib-level=9 "$TEMP_DMG"
hdiutil verify "$TEMP_DMG"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$DMG_MOUNT_POINT" "$TEMP_DMG"
DMG_MOUNTED=true
codesign --verify --deep --strict --all-architectures "$DMG_MOUNT_POINT/Cpin.app"
lipo "$DMG_MOUNT_POINT/Cpin.app/Contents/MacOS/Cpin" -verify_arch arm64 x86_64
[[ "$(readlink "$DMG_MOUNT_POINT/Applications")" == /Applications ]]
cmp "$PAYLOAD/使用说明.txt" "$DMG_MOUNT_POINT/使用说明.txt"
hdiutil detach "$DMG_MOUNT_POINT" -quiet
DMG_MOUNTED=false

mkdir -p "$ROOT/build"
cp "$TEMP_DMG" "$ROOT/build/$DMG_NAME"
cd "$ROOT/build"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
printf '\nDMG: %s\nSHA-256: %s\n' "$ROOT/build/$DMG_NAME" "$ROOT/build/$DMG_NAME.sha256"
