#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${REPO_ROOT}/core"
TARGET="${1:-aarch64-apple-ios}"

echo "=================================================================="
echo " Building Rust compose-ffi for target: ${TARGET}"
echo "=================================================================="

if command -v rustup >/dev/null 2>&1; then
    rustup target add "${TARGET}" || true
fi

(cd "${CORE_DIR}" && cargo rustc --target "${TARGET}" -p compose-ffi --release --lib --crate-type staticlib)

OUTPUT_LIB="${CORE_DIR}/target/${TARGET}/release/libcompose_ffi.a"
if [[ -f "${OUTPUT_LIB}" ]]; then
    echo "✓ Successfully built: ${OUTPUT_LIB} ($(du -h "${OUTPUT_LIB}" | cut -f1))"
else
    echo "Error: Expected static library not found at ${OUTPUT_LIB}" >&2
    exit 1
fi
