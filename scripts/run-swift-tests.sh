#!/usr/bin/env bash
# ==============================================================================
# scripts/run-swift-tests.sh
# Runs Swift package unit tests (on macOS/Linux with Swift) or performs
# structural and golden vector schema parity checks (on Linux without Swift).
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_KIT_DIR="${REPO_ROOT}/apple/Packages/ComposeKit"
SYNC_KIT_DIR="${REPO_ROOT}/apple/Packages/SyncKit"
CAPTURE_KIT_DIR="${REPO_ROOT}/apple/Packages/CaptureKit"
PERCEPTION_KIT_DIR="${REPO_ROOT}/apple/Packages/PerceptionKit"

echo "=================================================================="
echo " Running Swift Package Tests / Parity Verifications"
echo "=================================================================="

OS_NAME="$(uname -s)"

if [[ "${OS_NAME}" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
    echo "==> Detected macOS host with Swift compiler. Running native XCTests for Swift Packages..."
    swift test --package-path "${COMPOSE_KIT_DIR}" \
        -Xswiftc -I"${COMPOSE_KIT_DIR}/Sources/ComposeKit/Generated" \
        -Xswiftc -Xcc -Xswiftc -fmodule-map-file="${COMPOSE_KIT_DIR}/Sources/ComposeKit/Generated/compose_ffiFFI.modulemap" \
        -Xlinker -L"${REPO_ROOT}/core/target/debug" \
        -Xlinker -lcompose_ffi
    swift test --package-path "${CAPTURE_KIT_DIR}"
    swift test --package-path "${PERCEPTION_KIT_DIR}"
    swift test --package-path "${SYNC_KIT_DIR}"
    echo "✓ All Swift package tests passed."
else
    echo "==> Linux/Non-Darwin host. Running Swift structural & schema parity check..."
    python3 "${REPO_ROOT}/scripts/validate-swift-parity.py"
    echo "✓ Swift package structure & golden parity validated."
fi

echo "=================================================================="
echo " Swift Verification Succeeded (Code: 0)"
echo "=================================================================="
