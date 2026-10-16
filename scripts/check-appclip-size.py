#!/usr/bin/env python3
"""
scripts/check-appclip-size.py
App Clip Pure-Swift Architecture and Bundle Size Interceptor.
Enforces:
1. Architectural Decoupling: App Clip must have ZERO UniFFI, Rust, or C bindings.
2. Size Ceiling: Hard ceiling of 15 MB uncompressed, warning ceiling at 8 MB.
"""

import os
import re
import sys
from pathlib import Path

FORBIDDEN_PATTERNS = [
    re.compile(r"import\s+compose_ffi", re.IGNORECASE),
    re.compile(r"import\s+compose_core", re.IGNORECASE),
    re.compile(r"libcompose_core\.a", re.IGNORECASE),
    re.compile(r"uniffi", re.IGNORECASE),
    re.compile(r"compose_ffi", re.IGNORECASE),
]

WARNING_SIZE_BYTES = 8 * 1024 * 1024    # 8 MB Warning threshold
HARD_LIMIT_SIZE_BYTES = 15 * 1024 * 1024 # 15 MB Hard App Store ceiling

def check_file_forbidden_tokens(file_path: Path) -> list:
    violations = []
    try:
        content = file_path.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        return [f"Could not read {file_path}: {e}"]

    for line_no, line in enumerate(content.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        for pat in FORBIDDEN_PATTERNS:
            if pat.search(stripped):
                violations.append(
                    f"{file_path}:{line_no}: Forbidden Rust/UniFFI token matched '{pat.pattern}' -> {stripped}"
                )
    return violations

def calculate_directory_size(dir_path: Path) -> int:
    total_size = 0
    for root, _, files in os.walk(dir_path):
        for f in files:
            fp = Path(root) / f
            if fp.is_file():
                total_size += fp.stat().st_size
    return total_size

def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    app_clip_dir = repo_root / "apple" / "CameraAppClip"
    synckit_dir = repo_root / "apple" / "Packages" / "SyncKit"

    print("==================================================================")
    print(" App Clip Architecture Decoupling & Size Ceiling Auditor")
    print("==================================================================")
    print(f" App Clip Directory:  {app_clip_dir.relative_to(repo_root)}")
    print(f" SyncKit Directory:   {synckit_dir.relative_to(repo_root)}")
    print(f" Hard Size Ceiling:   {HARD_LIMIT_SIZE_BYTES / (1024 * 1024):.1f} MB (App Store limit)")
    print(f" Warning Threshold:   {WARNING_SIZE_BYTES / (1024 * 1024):.1f} MB")
    print("------------------------------------------------------------------")

    all_violations = []

    # 1. Check architectural isolation (No Rust / UniFFI imports)
    target_dirs = [app_clip_dir, synckit_dir]
    total_scanned_files = 0

    for target in target_dirs:
        if not target.exists():
            all_violations.append(f"Target directory {target} does not exist!")
            continue

        for root, _, files in os.walk(target):
            for file_name in files:
                p = Path(root) / file_name
                if p.suffix in [".swift", ".h", ".m", ".c", ".cpp", ".plist", ".xcconfig"]:
                    total_scanned_files += 1
                    file_violations = check_file_forbidden_tokens(p)
                    all_violations.extend(file_violations)

    print(f" [1] Scanned {total_scanned_files} Swift/Apple source files for Rust/UniFFI leakage.")

    # 2. Check total source & bundle size
    total_bytes = 0
    for target in target_dirs:
        if target.exists():
            total_bytes += calculate_directory_size(target)

    size_kb = total_bytes / 1024.0
    size_mb = total_bytes / (1024.0 * 1024.0)

    print(f" [2] Current App Clip component tree uncompressed payload: {size_kb:.2f} KB ({size_mb:.4f} MB).")

    if total_bytes > HARD_LIMIT_SIZE_BYTES:
        all_violations.append(
            f"App Clip size {size_mb:.2f} MB EXCEEDS hard ceiling of 15 MB! Will fail App Store distribution."
        )
    elif total_bytes > WARNING_SIZE_BYTES:
        print(f" [WARN] App Clip size {size_mb:.2f} MB exceeds warning threshold of 8 MB.")
    else:
        print(f" [OK] Size is well within 8 MB / 15 MB budget (< {(total_bytes / HARD_LIMIT_SIZE_BYTES) * 100:.2f}% of max).")

    print("------------------------------------------------------------------")
    if all_violations:
        print("[FAIL] App Clip architecture or size violations found:", file=sys.stderr)
        for v in all_violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("[SUCCESS] App Clip is 100% decoupled from Rust/UniFFI and within size limits.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
