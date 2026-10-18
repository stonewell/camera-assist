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
    echo "==> Building compose-ffi library..."
    (cd "${REPO_ROOT}/core" && cargo build -p compose-ffi)

    export DYLD_LIBRARY_PATH="${REPO_ROOT}/core/target/debug:${DYLD_LIBRARY_PATH:-}"

    echo "==> [1/4] Running ComposeKit tests..."
    swift test --package-path "${COMPOSE_KIT_DIR}" \
        -Xswiftc -I"${COMPOSE_KIT_DIR}/Sources/ComposeKit/Generated" \
        -Xswiftc -Xcc -Xswiftc -fmodule-map-file="${COMPOSE_KIT_DIR}/Sources/ComposeKit/Generated/compose_ffiFFI.modulemap" \
        -Xlinker -L"${REPO_ROOT}/core/target/debug" \
        -Xlinker -rpath -Xlinker "${REPO_ROOT}/core/target/debug" \
        -Xlinker -lcompose_ffi

    echo "==> [2/4] Running CaptureKit tests..."
    swift test --package-path "${CAPTURE_KIT_DIR}"

    echo "==> [3/4] Running PerceptionKit tests..."
    swift test --package-path "${PERCEPTION_KIT_DIR}"

    echo "==> [4/4] Running SyncKit tests..."
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
