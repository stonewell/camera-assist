#!/usr/bin/env python3
"""
scripts/check-appclip-size.py
App Clip Pure-Swift Architecture and Bundle Size Interceptor.
Enforces:
1. Architectural Decoupling: App Clip must have ZERO UniFFI, Rust, or C bindings.
2. Size Ceiling: Hard ceiling of 15 MB uncompressed, warning ceiling at 8 MB.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

FORBIDDEN_PATTERNS = [
    re.compile(r"import\s+ComposeKit", re.IGNORECASE),
    re.compile(r"import\s+compose_ffi", re.IGNORECASE),
    re.compile(r"import\s+compose_core", re.IGNORECASE),
    re.compile(r"libcompose_core\.a", re.IGNORECASE),
    re.compile(r"uniffi", re.IGNORECASE),
    re.compile(r"compose_ffi", re.IGNORECASE),
    # TASK-01: the prebuilt Rust FFI ships as a ComposeCore.xcframework binary target; an
    # App Clip must never declare or reference it (it must stay 100% pure Swift).
    re.compile(r"ComposeCore", re.IGNORECASE),
    re.compile(r"binaryTarget", re.IGNORECASE),
    re.compile(r"\.xcframework", re.IGNORECASE),
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
    for root, dirs, files in os.walk(dir_path):
        dirs[:] = [d for d in dirs if d not in [".build", ".bsp", ".git", ".swiftpm", "xtool", ".xtool"]]
        for f in files:
            fp = Path(root) / f
            if fp.is_file():
                total_size += fp.stat().st_size
    return total_size

def get_compiled_bundle_size(app_path: Path) -> tuple[int, str]:
    """Calculates total uncompressed payload bytes and du disk usage for a compiled .app bundle."""
    total_bytes = 0
    for root, _, files in os.walk(app_path):
        for f in files:
            fp = Path(root) / f
            try:
                total_bytes += fp.stat().st_size
            except OSError:
                pass
    du_str = "unknown"
    try:
        res = subprocess.run(
            ["du", "-sh", str(app_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            du_str = res.stdout.strip().split()[0]
    except Exception:
        pass
    return total_bytes, du_str

def main() -> int:
    parser = argparse.ArgumentParser(
        description="App Clip Architecture Decoupling & Size Ceiling Auditor"
    )
    parser.add_argument(
        "--source-only",
        action="store_true",
        help="Force measuring source bytes only, skipping compiled .app bundle check",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    app_clip_dir = repo_root / "apple" / "CameraAppClip"
    synckit_dir = repo_root / "apple" / "Packages" / "SyncKit"
    compiled_app = app_clip_dir / "xtool" / "CameraAppClip.app"

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

        for root, dirs, files in os.walk(target):
            dirs[:] = [d for d in dirs if d not in [".build", ".bsp", ".git", ".swiftpm", "xtool", ".xtool"]]
            for file_name in files:
                p = Path(root) / file_name
                if p.suffix in [".swift", ".h", ".m", ".c", ".cpp", ".plist", ".xcconfig"]:
                    total_scanned_files += 1
                    file_violations = check_file_forbidden_tokens(p)
                    all_violations.extend(file_violations)

    print(f" [1] Scanned {total_scanned_files} Swift/Apple source files for Rust/UniFFI leakage.")

    # 2. Check compiled .app size (TASK-02: du of CameraAppClip.app, falling back to source bytes)
    is_compiled = False
    total_bytes = 0

    if not args.source_only and compiled_app.is_dir():
        is_compiled = True
        total_bytes, du_str = get_compiled_bundle_size(compiled_app)
        size_kb = total_bytes / 1024.0
        size_mb = total_bytes / (1024.0 * 1024.0)
        print(f" [2] Compiled App Clip bundle detected at {compiled_app.relative_to(repo_root)}:")
        print(f"     Payload: {size_kb:.2f} KB ({size_mb:.4f} MB) uncompressed [du disk usage: {du_str}].")
    else:
        if args.source_only:
            print(" [2] Measuring App Clip component tree source bytes (--source-only mode requested):")
        else:
            print(f" [WARN] Compiled App Clip bundle not found at {compiled_app.relative_to(repo_root)}!")
            print(" [WARN] Falling back to measuring uncompressed source bytes. This does NOT reflect compiled binary size.")

        for target in target_dirs:
            if target.exists():
                total_bytes += calculate_directory_size(target)

        size_kb = total_bytes / 1024.0
        size_mb = total_bytes / (1024.0 * 1024.0)
        print(f"     Payload: {size_kb:.2f} KB ({size_mb:.4f} MB) uncompressed source bytes.")

    measurement_type = "Compiled binary bundle" if is_compiled else "Source-only payload"
    if total_bytes > HARD_LIMIT_SIZE_BYTES:
        all_violations.append(
            f"App Clip size ({measurement_type}) {size_mb:.2f} MB EXCEEDS hard ceiling of 15 MB! Will fail App Store distribution."
        )
    elif total_bytes > WARNING_SIZE_BYTES:
        print(f" [WARN] App Clip size ({measurement_type}) {size_mb:.2f} MB exceeds warning threshold of 8 MB.")
    else:
        print(f" [OK] Size ({measurement_type}) is well within 8 MB / 15 MB budget (< {(total_bytes / HARD_LIMIT_SIZE_BYTES) * 100:.2f}% of max).")

    print("------------------------------------------------------------------")
    if all_violations:
        print("[FAIL] App Clip architecture or size violations found:", file=sys.stderr)
        for v in all_violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print(f"[SUCCESS] App Clip is 100% decoupled from Rust/UniFFI and within size limits ({measurement_type}).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
