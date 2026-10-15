#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/.build/ModuleCache"
PANEL_CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpin-panel-checks.XXXXXX")"
trap 'rm -rf "$PANEL_CHECK_DIRECTORY"' EXIT

swiftc -emit-module -emit-library -module-name CpinCore \
    -module-cache-path "$ROOT/.build/ModuleCache" \
    Sources/CpinCore/*.swift \
    -emit-module-path "$PANEL_CHECK_DIRECTORY/CpinCore.swiftmodule" \
    -o "$PANEL_CHECK_DIRECTORY/libCpinCore.dylib"
swiftc -D STANDALONE_CHECKS -module-cache-path "$ROOT/.build/ModuleCache" \
    -I "$PANEL_CHECK_DIRECTORY" -L "$PANEL_CHECK_DIRECTORY" -lCpinCore \
    -Xlinker -rpath -Xlinker "$PANEL_CHECK_DIRECTORY" \
    Sources/Cpin/PanelController.swift Sources/Cpin/AppModel.swift \
    Sources/Cpin/ShelfView.swift Sources/Cpin/ClipCardView.swift Sources/Cpin/Theme.swift \
    Tests/PanelControllerChecks.swift -o "$PANEL_CHECK_DIRECTORY/panel-checks"
"$PANEL_CHECK_DIRECTORY/panel-checks"
