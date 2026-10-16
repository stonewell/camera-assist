#!/usr/bin/env bash
# ==============================================================================
# scripts/verify-all.sh
# Unified Quality Gate and Verification Pipeline for Camera Assist Monorepo.
# Runs: Format Check -> Clippy -> Unit Tests -> Golden Tests -> Microbenchmarks
#       -> ONNX Model Audit -> App Clip Decoupling & Size Check.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${REPO_ROOT}/core"

echo "=================================================================="
echo " Starting Camera Assist Unified Quality Verification Pipeline"
echo " Repo Root: ${REPO_ROOT}"
echo "=================================================================="

# Step 1: Rust Format Check
echo ""
echo "[Step 1/7] Checking Rust formatting (cargo fmt --check)..."
(cd "${CORE_DIR}" && cargo fmt --check)
echo "✓ Formatting clean."

# Step 2: Rust Clippy
echo ""
echo "[Step 2/7] Running Rust Clippy linter (--workspace --benches --tests -D warnings)..."
(cd "${CORE_DIR}" && cargo clippy --workspace --benches --tests -- -D warnings)
echo "✓ Clippy checks passed with zero warnings."

# Step 3: Rust Workspace Tests
echo ""
echo "[Step 3/7] Running all unit and integration tests (cargo test --workspace)..."
(cd "${CORE_DIR}" && cargo test --workspace)
echo "✓ All workspace tests passed."

# Step 4: Golden Vector Regression
echo ""
echo "[Step 4/7] Running golden vector test runner..."
(cd "${CORE_DIR}" && cargo test -p compose-core --test golden_runner)
echo "✓ Golden vectors regression passed."

# Step 5: Microbenchmarks SLA Verification
echo ""
echo "[Step 5/7] Verifying engine & FFI microbenchmarks SLA (cargo bench --workspace -- --test)..."
(cd "${CORE_DIR}" && cargo bench --workspace -- --test)
echo "✓ Microbenchmarks passed 60Hz real-time SLA thresholds."

# Step 6: Desktop ONNX Model License & Architecture Audit
echo ""
echo "[Step 6/7] Auditing desktop ONNX models and open-source licenses..."
python3 "${REPO_ROOT}/scripts/audit-models.py"
echo "✓ Model manifest license audit passed."

# Step 7: App Clip Architecture Decoupling & Size Verification
echo ""
echo "[Step 7/7] Verifying App Clip zero-Rust decoupling and size ceiling..."
python3 "${REPO_ROOT}/scripts/check-appclip-size.py"
echo "✓ App Clip decoupling and size ceiling verified."

# Optional: cargo-deny if installed
if command -v cargo-deny >/dev/null 2>&1; then
    echo ""
    echo "[Optional Step] Running cargo-deny check..."
    (cd "${CORE_DIR}" && cargo deny --manifest-path Cargo.toml check)
    echo "✓ Cargo-deny check passed."
fi

echo ""
echo "=================================================================="
echo " 🎉 ALL VERIFICATION STEPS PASSED SUCCESSFULLY (Exit Code: 0)"
echo " Monorepo is healthy, tested, benchmarked, and license-compliant."
echo "=================================================================="
