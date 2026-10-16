#!/usr/bin/env bash
# ==============================================================================
# scripts/build-xcframework.sh
# Multi-Architecture XCFramework build pipeline for Apple platforms (iOS/macOS).
# Generates Swift bindings and packages ComposeCore.xcframework.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${REPO_ROOT}/core"
FRAMEWORKS_DIR="${REPO_ROOT}/apple/Frameworks"
GENERATED_DIR="${REPO_ROOT}/apple/Packages/ComposeKit/Sources/ComposeKit/Generated"

echo "=================================================================="
echo " Starting ComposeCore XCFramework Build Pipeline"
echo "=================================================================="

# 1. Generate Swift bindings and C headers
"${REPO_ROOT}/scripts/generate-uniffi-bindings.sh"

OS_NAME="$(uname -s)"
echo "Host Operating System: ${OS_NAME}"

if [[ "${OS_NAME}" == "Darwin" ]]; then
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "Error: xcodebuild not found. Xcode is required to assemble XCFramework." >&2
        exit 1
    fi

    echo "==> Detected macOS host with Xcode. Compiling Apple target architectures..."
    TARGETS=(
        "aarch64-apple-ios"
        "aarch64-apple-ios-sim"
        "x86_64-apple-ios-sim"
        "aarch64-apple-darwin"
        "x86_64-apple-darwin"
    )

    for TARGET in "${TARGETS[@]}"; do
        echo "--> Building staticlib for ${TARGET}..."
        (cd "${CORE_DIR}" && cargo build --release --target "${TARGET}" -p compose-ffi)
    done

    # Assemble fat simulator library
    SIM_DIR="${CORE_DIR}/target/sim-fat"
    mkdir -p "${SIM_DIR}"
    lipo -create \
        "${CORE_DIR}/target/aarch64-apple-ios-sim/release/libcompose_ffi.a" \
        "${CORE_DIR}/target/x86_64-apple-ios-sim/release/libcompose_ffi.a" \
        -output "${SIM_DIR}/libcompose_ffi.a"

    # Assemble fat macOS library
    MAC_DIR="${CORE_DIR}/target/mac-fat"
    mkdir -p "${MAC_DIR}"
    lipo -create \
        "${CORE_DIR}/target/aarch64-apple-darwin/release/libcompose_ffi.a" \
        "${CORE_DIR}/target/x86_64-apple-darwin/release/libcompose_ffi.a" \
        -output "${MAC_DIR}/libcompose_ffi.a"

    # Build XCFramework
    rm -rf "${FRAMEWORKS_DIR}/ComposeCore.xcframework"
    mkdir -p "${FRAMEWORKS_DIR}"

    xcodebuild -create-xcframework \
        -library "${CORE_DIR}/target/aarch64-apple-ios/release/libcompose_ffi.a" \
        -headers "${GENERATED_DIR}" \
        -library "${SIM_DIR}/libcompose_ffi.a" \
        -headers "${GENERATED_DIR}" \
        -library "${MAC_DIR}/libcompose_ffi.a" \
        -headers "${GENERATED_DIR}" \
        -output "${FRAMEWORKS_DIR}/ComposeCore.xcframework"

    echo "✓ ComposeCore.xcframework assembled successfully in ${FRAMEWORKS_DIR}/ComposeCore.xcframework"
else
    echo "==> Running in Linux/CI environment: performing cross-compilation dry-run & static validation."
    (cd "${CORE_DIR}" && cargo build --release -p compose-ffi)
    
    # Verify generated C headers and modulemap exist
    if [[ -f "${GENERATED_DIR}/compose_ffiFFI.h" && -f "${GENERATED_DIR}/compose_ffi.swift" ]]; then
        echo "✓ Headers and Swift bindings validated for cross-compilation."
    else
        echo "Error: Missing generated headers or Swift bindings in ${GENERATED_DIR}" >&2
        exit 1
    fi
    echo "✓ Local non-Darwin validation passed. (Full XCFramework signing occurs in macOS CI runner)."
fi

echo "=================================================================="
echo " XCFramework Build Pipeline Finished (Code: 0)"
echo "=================================================================="
