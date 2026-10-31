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
    run_pkg_test() {
        local name="$1"
        shift
        echo "------------------------------------------------------------------"
        echo "==> Running ${name} tests..."
        echo "------------------------------------------------------------------"
        local log_file
        log_file="$(mktemp)"
        if ! "$@" > "${log_file}" 2>&1; then
            cat "${log_file}"
            if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
                local short_err
                short_err="$(tail -n 25 "${log_file}" | tr '\n' ' ')"
                echo "::error title=${name} Tests Failed::${short_err}"
            fi
            rm -f "${log_file}"
            return 1
        fi
        cat "${log_file}"
        rm -f "${log_file}"
        echo "✓ ${name} tests passed."
    }

    echo "==> Building ComposeCore.xcframework (iOS device + simulator + macOS)..."
    # TASK-01: ComposeKit links the Rust static library through this local binary target.
    "${REPO_ROOT}/scripts/build-xcframework.sh"

    # Hard gate: the ComposeKit manifest fails fast if the XCFramework is missing, so a
    # green ComposeKit run can never be a silent mock run.
    export COMPOSE_REQUIRE_FFI=1

    run_pkg_test "ComposeKit" swift test --package-path "${COMPOSE_KIT_DIR}"

    run_pkg_test "CaptureKit" swift test --package-path "${CAPTURE_KIT_DIR}"

    run_pkg_test "PerceptionKit" swift test --package-path "${PERCEPTION_KIT_DIR}"

    run_pkg_test "SyncKit" swift test --package-path "${SYNC_KIT_DIR}"

    echo "✓ All Swift package tests passed."
else
    echo "==> Linux/Non-Darwin host. Running Swift structural & schema parity check..."
    echo "    NOTE: real linking (ComposeCore.xcframework) and real-engine execution"
    echo "    (13 golden vectors via 'swift test') require macOS / a physical device."
    python3 "${REPO_ROOT}/scripts/validate-swift-parity.py"
    echo "✓ Swift package structure & golden parity validated."
fi

echo "=================================================================="
echo " Swift Verification Succeeded (Code: 0)"
echo "=================================================================="
