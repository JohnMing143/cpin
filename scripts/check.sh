#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/.build/checks"
swiftc -D STANDALONE_CHECKS -module-cache-path "$ROOT/.build/ModuleCache" \
    Sources/CpinCore/*.swift \
    Tests/CpinCoreTests/StandaloneChecks.swift \
    -o "$ROOT/.build/checks/core-checks"
"$ROOT/.build/checks/core-checks"

# A private, named pasteboard keeps the user's system clipboard untouched.
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpin-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIRECTORY"' EXIT
swiftc -emit-module -emit-library -module-name CpinCore \
    -module-cache-path "$ROOT/.build/ModuleCache" \
    Sources/CpinCore/*.swift \
    -emit-module-path "$CHECK_DIRECTORY/CpinCore.swiftmodule" \
    -o "$CHECK_DIRECTORY/libCpinCore.dylib"
swiftc -D STANDALONE_CHECKS -module-cache-path "$ROOT/.build/ModuleCache" \
    -I "$CHECK_DIRECTORY" -L "$CHECK_DIRECTORY" -lCpinCore \
    -Xlinker -rpath -Xlinker "$CHECK_DIRECTORY" \
    Sources/Cpin/ClipboardMonitor.swift Tests/ClipboardMonitorChecks.swift \
    -o "$CHECK_DIRECTORY/monitor-checks"
"$CHECK_DIRECTORY/monitor-checks"
swiftc -D STANDALONE_CHECKS -parse-as-library -module-cache-path "$ROOT/.build/ModuleCache" \
    -I "$CHECK_DIRECTORY" -L "$CHECK_DIRECTORY" -lCpinCore \
    -Xlinker -rpath -Xlinker "$CHECK_DIRECTORY" \
    Tests/PanelGeometryChecks.swift -o "$CHECK_DIRECTORY/geometry-checks"
"$CHECK_DIRECTORY/geometry-checks"
swiftc -D STANDALONE_CHECKS -module-cache-path "$ROOT/.build/ModuleCache" \
    -I "$CHECK_DIRECTORY" -L "$CHECK_DIRECTORY" -lCpinCore \
    -Xlinker -rpath -Xlinker "$CHECK_DIRECTORY" \
    Sources/Cpin/AppModel.swift Tests/AppModelChecks.swift -o "$CHECK_DIRECTORY/model-checks"
"$CHECK_DIRECTORY/model-checks"
