#!/usr/bin/env bash
# ==============================================================================
# scripts/generate-uniffi-bindings.sh
# Generates Swift bindings and C headers from compose-ffi crate via uniffi-bindgen.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${REPO_ROOT}/core"
OUTPUT_DIR="${REPO_ROOT}/apple/Packages/ComposeKit/Sources/ComposeKit/Generated"

mkdir -p "${OUTPUT_DIR}"

echo "==> Building compose-ffi cdylib..."
(cd "${CORE_DIR}" && cargo build -p compose-ffi)

# Detect host cdylib extension (.so on Linux, .dylib on macOS)
if [[ -f "${CORE_DIR}/target/debug/libcompose_ffi.so" ]]; then
    CDYLIB_PATH="${CORE_DIR}/target/debug/libcompose_ffi.so"
elif [[ -f "${CORE_DIR}/target/debug/libcompose_ffi.dylib" ]]; then
    CDYLIB_PATH="${CORE_DIR}/target/debug/libcompose_ffi.dylib"
else
    echo "Error: libcompose_ffi cdylib not found in target/debug" >&2
    exit 1
fi

echo "==> Generating Swift bindings via uniffi-bindgen..."
(cd "${CORE_DIR}" && cargo run --bin uniffi-bindgen generate --library "${CDYLIB_PATH}" --language swift --out-dir "${OUTPUT_DIR}" --no-format)

echo "==> Swift bindings successfully generated in:"
echo "    ${OUTPUT_DIR}"
ls -la "${OUTPUT_DIR}"
