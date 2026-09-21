#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_root=$(mktemp -d /tmp/tamor-tests.XXXXXX)
trap 'rm -rf "$test_root"' EXIT
swiftc -O -module-cache-path "$test_root/cache" Sources/Core/JewelCatalog.swift Sources/Core/JewelSave.swift Sources/Core/CaratCollection.swift Sources/Core/PlayerProgress.swift Tests/Core/main.swift -o "$test_root/core"
"$test_root/core"
swiftc -O -module-cache-path "$test_root/cache" Sources/Core/JewelSave.swift Sources/Core/CaratCollection.swift Sources/Core/PlayerProgress.swift Sources/Core/MiniGameEngine.swift Sources/Core/GameRules.swift Tests/Rules/main.swift -o "$test_root/rules"
"$test_root/rules"
