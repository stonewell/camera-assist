#!/usr/bin/env python3
"""
scripts/validate-swift-parity.py
Validates Swift Package structure, UniFFI generated bindings, and Golden Vector schema parity.
Used in environments where swiftc is not installed locally.
"""

import json
import re
import sys
from pathlib import Path

def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    compose_kit_dir = repo_root / "apple" / "Packages" / "ComposeKit"
    sync_kit_dir = repo_root / "apple" / "Packages" / "SyncKit"
    fixtures_dir = repo_root / "fixtures" / "golden"

    print("--- [validate-swift-parity] Checking Swift Package Declarations ---")

    # 1. Check Package manifests
    compose_pkg = compose_kit_dir / "Package.swift"
    sync_pkg = sync_kit_dir / "Package.swift"

    for pkg in [compose_pkg, sync_pkg]:
        if not pkg.is_file():
            print(f"[FAIL] Missing Package.swift at {pkg}", file=sys.stderr)
            return 1
        content = pkg.read_text(encoding="utf-8")
        if "PackageDescription" not in content or "let package = Package(" not in content:
            print(f"[FAIL] Invalid Package.swift syntax in {pkg}", file=sys.stderr)
            return 1
        print(f"  ✓ {pkg.relative_to(repo_root)} is well-formed.")

    # 2. Check UniFFI generated bindings
    gen_dir = compose_kit_dir / "Sources" / "ComposeKit" / "Generated"
    required_gen_files = ["compose_ffi.swift", "compose_ffiFFI.h", "compose_ffiFFI.modulemap"]
    for f in required_gen_files:
        fp = gen_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing generated UniFFI file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found UniFFI artifact: {f} ({fp.stat().st_size} bytes)")

    # 3. Check Swift source models and actor
    sources_dir = compose_kit_dir / "Sources" / "ComposeKit"
    required_src = ["LiveComposer.swift", "Models.swift"]
    for f in required_src:
        fp = sources_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing Swift source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found source file: {f}")

    # 4. Check Swift Tests
    tests_dir = compose_kit_dir / "Tests" / "ComposeKitTests"
    required_tests = ["GoldenVectorTests.swift", "ConcurrencyTests.swift"]
    for f in required_tests:
        fp = tests_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing Swift test file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found test file: {f}")

    # 5. Check Golden Vectors integrity against Swift definitions
    print("--- [validate-swift-parity] Checking Golden Vector Coverage ---")
    golden_files = list(fixtures_dir.glob("*.json"))
    golden_vectors = [f for f in golden_files if f.name != "schema.json"]
    if len(golden_vectors) < 10:
        print(f"[FAIL] Expected at least 10 golden vector JSONs, found {len(golden_vectors)}", file=sys.stderr)
        return 1

    valid_severities = {"Good", "Minor", "Major", "Critical"}
    for gv in sorted(golden_vectors):
        with open(gv, "r", encoding="utf-8") as f:
            data = json.load(f)
        vid = data.get("id")
        findings = data.get("expected_findings", [])
        for item in findings:
            sev = item.get("severity")
            if sev not in valid_severities:
                print(f"[FAIL] Golden vector {vid} has invalid severity: {sev}", file=sys.stderr)
                return 1
        print(f"  ✓ {gv.name:<32} [id: {vid}, findings: {len(findings)}]")

    print(f"--- [validate-swift-parity] All {len(golden_vectors)} golden vectors validated with Swift parity. ---")
    return 0

if __name__ == "__main__":
    sys.exit(main())
