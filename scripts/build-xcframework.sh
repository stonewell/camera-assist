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
    run_step() {
        local name="$1"
        shift
        echo "------------------------------------------------------------------"
        echo "==> ${name}..."
        echo "------------------------------------------------------------------"
        local log_file
        log_file="$(mktemp)"
        if ! "$@" > "${log_file}" 2>&1; then
            cat "${log_file}"
            if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
                local short_err
                short_err="$(tail -n 25 "${log_file}" | tr '\n' ' ')"
                echo "::error title=${name} Failed::${short_err}"
            fi
            rm -f "${log_file}"
            return 1
        fi
        cat "${log_file}"
        rm -f "${log_file}"
    }

    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "Error: xcodebuild not found. Xcode is required to assemble XCFramework." >&2
        exit 1
    fi

    echo "==> Detected macOS host with Xcode. Compiling Apple target architectures..."
    TARGETS=(
        "aarch64-apple-ios"
        "aarch64-apple-ios-sim"
        "x86_64-apple-ios"
        "aarch64-apple-darwin"
        "x86_64-apple-darwin"
    )

    # Stage public C headers and modulemap for xcframework
    HEADERS_DIR="${CORE_DIR}/target/xcframework-headers"
    rm -rf "${HEADERS_DIR}"
    mkdir -p "${HEADERS_DIR}"
    cp "${GENERATED_DIR}/compose_ffiFFI.h" "${HEADERS_DIR}/"
    cp "${GENERATED_DIR}/compose_ffiFFI.modulemap" "${HEADERS_DIR}/module.modulemap"

    for TARGET in "${TARGETS[@]}"; do
        echo "--> Ensuring rust target ${TARGET} is installed..."
        rustup target add "${TARGET}"
        echo "--> Building staticlib for ${TARGET}..."
        (cd "${CORE_DIR}" && cargo build --release --target "${TARGET}" -p compose-ffi --lib)
    done

    # Assemble fat simulator library
    SIM_DIR="${CORE_DIR}/target/sim-fat"
    mkdir -p "${SIM_DIR}"
    run_step "Assemble Fat iOS Simulator Archive" lipo -create \
        "${CORE_DIR}/target/aarch64-apple-ios-sim/release/libcompose_ffi.a" \
        "${CORE_DIR}/target/x86_64-apple-ios/release/libcompose_ffi.a" \
        -output "${SIM_DIR}/libcompose_ffi.a"

    # Assemble fat macOS library
    MAC_DIR="${CORE_DIR}/target/mac-fat"
    mkdir -p "${MAC_DIR}"
    run_step "Assemble Fat macOS Archive" lipo -create \
        "${CORE_DIR}/target/aarch64-apple-darwin/release/libcompose_ffi.a" \
        "${CORE_DIR}/target/x86_64-apple-darwin/release/libcompose_ffi.a" \
        -output "${MAC_DIR}/libcompose_ffi.a"

    # Build XCFramework
    rm -rf "${FRAMEWORKS_DIR}/ComposeCore.xcframework"
    mkdir -p "${FRAMEWORKS_DIR}"

    run_step "Create XCFramework" xcodebuild -create-xcframework \
        -library "${CORE_DIR}/target/aarch64-apple-ios/release/libcompose_ffi.a" \
        -headers "${HEADERS_DIR}" \
        -library "${SIM_DIR}/libcompose_ffi.a" \
        -headers "${HEADERS_DIR}" \
        -library "${MAC_DIR}/libcompose_ffi.a" \
        -headers "${HEADERS_DIR}" \
        -output "${FRAMEWORKS_DIR}/ComposeCore.xcframework"

    echo "✓ ComposeCore.xcframework assembled successfully in ${FRAMEWORKS_DIR}/ComposeCore.xcframework"
else
    echo "==> Running in Linux/CI environment: building aarch64-apple-ios staticlib and assembling XCFramework."
    if command -v rustup >/dev/null 2>&1; then
        rustup target add aarch64-apple-ios || true
    fi

    echo "--> Building staticlib for aarch64-apple-ios..."
    (cd "${CORE_DIR}" && cargo rustc --target aarch64-apple-ios -p compose-ffi --release --lib --crate-type staticlib)

    IOS_LIB="${CORE_DIR}/target/aarch64-apple-ios/release/libcompose_ffi.a"
    if [[ ! -f "${IOS_LIB}" ]]; then
        echo "Error: Expected static library not found at ${IOS_LIB}" >&2
        exit 1
    fi

    # Verify generated C headers and modulemap exist
    if [[ ! -f "${GENERATED_DIR}/compose_ffiFFI.h" || ! -f "${GENERATED_DIR}/compose_ffiFFI.modulemap" ]]; then
        echo "Error: Missing generated C headers or modulemap in ${GENERATED_DIR}" >&2
        exit 1
    fi

    XCF_DIR="${FRAMEWORKS_DIR}/ComposeCore.xcframework"
    rm -rf "${XCF_DIR}"
    mkdir -p "${XCF_DIR}/ios-arm64/Headers"

    cp "${IOS_LIB}" "${XCF_DIR}/ios-arm64/libcompose_ffi.a"
    cp "${GENERATED_DIR}/compose_ffiFFI.h" "${XCF_DIR}/ios-arm64/Headers/compose_ffiFFI.h"
    cp "${GENERATED_DIR}/compose_ffiFFI.modulemap" "${XCF_DIR}/ios-arm64/Headers/module.modulemap"

    cat << 'EOF' > "${XCF_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key>
			<string>libcompose_ffi.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>libcompose_ffi.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF

    echo "✓ ComposeCore.xcframework assembled successfully in ${XCF_DIR}"
fi

echo "=================================================================="
echo " XCFramework Build Pipeline Finished (Code: 0)"
echo "=================================================================="
