#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc Sources/Ent303Rise/MovementEngine.swift \
  Sources/Ent303Rise/MovementSession.swift Tests/MovementChecks.swift \
  -o "$CHECK_DIR/movement-checks"
"$CHECK_DIR/movement-checks"
