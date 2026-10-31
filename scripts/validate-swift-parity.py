#!/usr/bin/env python3
"""
scripts/validate-swift-parity.py
Validates Swift Package structure, UniFFI generated bindings, PerceptionKit <-> compose-core
JSON schema parity, and Golden Vector schema parity.
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
    capture_kit_dir = repo_root / "apple" / "Packages" / "CaptureKit"
    perception_kit_dir = repo_root / "apple" / "Packages" / "PerceptionKit"
    camera_app_dir = repo_root / "apple" / "CameraApp"
    fixtures_dir = repo_root / "fixtures" / "golden"

    print("--- [validate-swift-parity] Checking Swift Package Declarations ---")

    # 1. Check Package manifests
    packages = [
        compose_kit_dir / "Package.swift",
        sync_kit_dir / "Package.swift",
        capture_kit_dir / "Package.swift",
        perception_kit_dir / "Package.swift"
    ]

    for pkg in packages:
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

    # 3. Check ComposeKit Swift source models and actor
    sources_dir = compose_kit_dir / "Sources" / "ComposeKit"
    required_src = ["LiveComposer.swift", "Models.swift"]
    for f in required_src:
        fp = sources_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing ComposeKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found source file: {f}")

    # 4. Check CaptureKit sources and tests
    print("--- [validate-swift-parity] Checking CaptureKit & PerceptionKit Components ---")
    capture_src = capture_kit_dir / "Sources" / "CaptureKit"
    capture_files = [
        "CaptureConfiguration.swift",
        "CaptureSessionManager.swift",
        "CapturePhotoController.swift",
        "RotationCoordinatorBridge.swift",
        "VisionOrientationMapper.swift"
    ]
    for f in capture_files:
        fp = capture_src / f
        if not fp.is_file():
            print(f"[FAIL] Missing CaptureKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found CaptureKit source: {f}")

    capture_test_file = capture_kit_dir / "Tests" / "CaptureKitTests" / "CaptureKitTests.swift"
    if not capture_test_file.is_file():
        print(f"[FAIL] Missing CaptureKit test file: {capture_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found CaptureKit test suite: CaptureKitTests.swift")

    # 5. Check PerceptionKit sources and tests
    perception_src = perception_kit_dir / "Sources" / "PerceptionKit"
    perception_files = [
        perception_src / "Pipeline" / "PerceptionModels.swift",
        perception_src / "Pipeline" / "FrameSyncHub.swift",
        perception_src / "Pipeline" / "PerceptionScheduler.swift",
        perception_src / "Motion" / "OneEuroFilter.swift",
        perception_src / "Motion" / "AttitudeTracker.swift",
        perception_src / "Vision" / "BodyPoseAnalyzer.swift",
        perception_src / "Vision" / "MaskSummarizer.swift",
        perception_src / "Vision" / "SubjectTracker.swift"
    ]
    for fp in perception_files:
        if not fp.is_file():
            print(f"[FAIL] Missing PerceptionKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found PerceptionKit source: {fp.name}")

    # 5b. Verify PerceptionModels.swift <-> compose-core JSON schema parity
    print("--- [validate-swift-parity] Verifying PerceptionModels.swift <-> compose-core Schema Parity ---")
    models_text = (perception_src / "Pipeline" / "PerceptionModels.swift").read_text(encoding="utf-8")
    required_schema_tokens = [
        "public var id: UInt32",
        "public var bounds: NormalizedBox",
        "public var joint_type: JointType",
        "public var point: NormalizedPoint",
        "public var mask_summary: MaskSummary?",
        "public var head_cols: [Float]",
        "public var torso_cols: [Float]",
        "public var leg_cols: [Float]",
        "public var angular_speed: Float",
        "public var is_flatish: Bool",
        "case Neck",
        "case Root"
    ]
    for token in required_schema_tokens:
        if token not in models_text:
            print(f"[FAIL] PerceptionModels.swift missing compose-core schema token: {token}", file=sys.stderr)
            return 1
    print("  ✓ PerceptionModels.swift matches compose-core Frame/Subject/Joint/MaskSummary/Posture schema 100%.")

    perception_test_file = perception_kit_dir / "Tests" / "PerceptionKitTests" / "PerceptionKitTests.swift"
    if not perception_test_file.is_file():
        print(f"[FAIL] Missing PerceptionKit test file: {perception_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found PerceptionKit test suite: PerceptionKitTests.swift")

    # 6. Check Perception Debug HUD
    debug_hud_file = camera_app_dir / "CameraFeature" / "PerceptionDebugHUD.swift"
    if not debug_hud_file.is_file():
        print(f"[FAIL] Missing PerceptionDebugHUD file: {debug_hud_file}", file=sys.stderr)
        return 1
    print(f"  ✓ Found CameraApp UI component: {debug_hud_file.name}")

    # 7. Check ComposeKit & SyncKit Tests
    tests_dir = compose_kit_dir / "Tests" / "ComposeKitTests"
    required_tests = ["GoldenVectorTests.swift", "ConcurrencyTests.swift"]
    for f in required_tests:
        fp = tests_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing Swift test file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found test file: {f}")

    sync_test_file = sync_kit_dir / "Tests" / "SyncKitTests" / "SyncKitTests.swift"
    if not sync_test_file.is_file():
        print(f"[FAIL] Missing SyncKit test file: {sync_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found SyncKit test suite: SyncKitTests.swift")

    # 8. Check Golden Vectors integrity against Swift definitions
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

    # 9. TASK-01 hard gate: ComposeKit must really link compose-ffi and must never silently mock
    print("--- [validate-swift-parity] Checking ComposeKit FFI Wiring (TASK-01) ---")

    compose_manifest = (compose_kit_dir / "Package.swift").read_text(encoding="utf-8")
    live_composer_path = compose_kit_dir / "Sources" / "ComposeKit" / "LiveComposer.swift"
    live_composer = live_composer_path.read_text(encoding="utf-8")
    run_swift_tests_path = repo_root / "scripts" / "run-swift-tests.sh"
    run_swift_tests = run_swift_tests_path.read_text(encoding="utf-8")

    # 9.1 Package.swift must reference the XCFramework through a binaryTarget and depend on it.
    # Comments in the manifest are stripped first: the design notes above mention
    # "ComposeCore.xcframework" and ".binaryTarget", and matching raw text would make these
    # assertions true no matter what the executable code does.
    compose_manifest_code = re.sub(r"//[^\n]*", "", compose_manifest)

    def delimited_block(text: str, open_index: int) -> str:
        depth = 0
        for idx in range(open_index, len(text)):
            char = text[idx]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return text[open_index + 1: idx]
        return text[open_index + 1:]

    if "ComposeCore.xcframework" not in compose_manifest_code:
        print(
            "[FAIL] ComposeKit/Package.swift does not reference ComposeCore.xcframework in code "
            "(a comment mentioning it is not enough: ComposeKit would build without the Rust engine)",
            file=sys.stderr,
        )
        return 1
    binary_target_match = re.search(
        r'\.binaryTarget\s*\(\s*name:\s*"ComposeCore"\s*,\s*path:\s*[^)]*\)',
        compose_manifest_code,
    )
    if binary_target_match is None:
        print(
            "[FAIL] ComposeKit/Package.swift declares no active "
            '`.binaryTarget(name: "ComposeCore", path: ...)`; deleting or commenting that line '
            "silently drops the Rust static library from the build",
            file=sys.stderr,
        )
        return 1
    compose_target_match = re.search(r'\.target\(\s*name:\s*"ComposeKit"', compose_manifest_code)
    if compose_target_match is None:
        print("[FAIL] ComposeKit/Package.swift has no ComposeKit target declaration", file=sys.stderr)
        return 1
    compose_target_open = compose_manifest_code.index("(", compose_target_match.start())
    compose_target_segment = delimited_block(compose_manifest_code, compose_target_open)
    if "dependencies" not in compose_target_segment or '"ComposeCore"' not in compose_target_segment:
        print(
            "[FAIL] ComposeKit target does not depend on the ComposeCore binary target "
            "(the ComposeKit .target(...) block must list \"ComposeCore\" in dependencies)",
            file=sys.stderr,
        )
        return 1
    if "unsafeFlags" in compose_manifest_code:
        print(
            "[FAIL] ComposeKit/Package.swift uses unsafeFlags; SwiftPM forbids dependents on "
            "such packages (use the ComposeCore binaryTarget instead)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ Package.swift links ComposeCore.xcframework via a .binaryTarget dependency.")

    # 9.2 The public initializer must be throwing and must not enable mock mode
    init_match = re.search(r"public init\([^)]*\)\s*(throws\s*)?\{", live_composer)
    if init_match is None:
        print("[FAIL] LiveComposer.swift has no public init(...) initializer", file=sys.stderr)
        return 1

    def block_body(text: str, brace_index: int) -> str:
        depth = 0
        for idx in range(brace_index, len(text)):
            char = text[idx]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return text[brace_index + 1: idx]
        return text[brace_index + 1:]

    init_open = init_match.end() - 1
    init_body = block_body(live_composer, init_open)
    if init_match.group(1) is None:
        print(
            "[FAIL] LiveComposer public init is not `throws`; engine failures would be hidden",
            file=sys.stderr,
        )
        return 1
    if re.search(r"isMockMode\s*=\s*true", init_body):
        print(
            "[FAIL] LiveComposer public init still enables mock mode (silent fallback)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ LiveComposer public init is throwing and never enables mock mode.")

    # 9.3 createMock() must be DEBUG-only
    composer_lines = live_composer.splitlines()
    create_mock_index = next(
        (i for i, line in enumerate(composer_lines) if "func createMock" in line),
        None,
    )
    if create_mock_index is None:
        print("[FAIL] LiveComposer.createMock() is missing", file=sys.stderr)
        return 1

    depth = 0
    in_debug_block = False
    for idx in range(create_mock_index, -1, -1):
        stripped = composer_lines[idx].strip()
        if stripped.startswith("#endif"):
            depth += 1
        elif stripped.startswith("#if"):
            if depth > 0:
                depth -= 1
            else:
                in_debug_block = re.match(r"#if\s+DEBUG\b", stripped) is not None
                break
    if not in_debug_block:
        print(
            "[FAIL] LiveComposer.createMock() is not wrapped in `#if DEBUG`; mock mode could "
            "ship in release builds",
            file=sys.stderr,
        )
        return 1
    print("  ✓ createMock() is confined to a `#if DEBUG` block.")

    # 9.4 No mock evaluator anywhere
    if "evaluateMockJson" in live_composer:
        print(
            "[FAIL] LiveComposer.swift still contains evaluateMockJson (silent mock fallback)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ LiveComposer.swift contains no mock evaluator.")

    # 9.5 macOS test runner must enforce the FFI link gate with a real export, not a comment
    run_swift_tests_code = re.sub(r"^[ \t]*#[^\n]*", "", run_swift_tests, flags=re.MULTILINE)
    if not re.search(r'^\s*export\s+COMPOSE_REQUIRE_FFI=1\s*$', run_swift_tests_code, re.MULTILINE):
        print(
            "[FAIL] scripts/run-swift-tests.sh has no active `export COMPOSE_REQUIRE_FFI=1` line; "
            "a commented-out gate never reaches the manifest, so the XCFramework fatalError guard "
            "would never fire on CI or device builds",
            file=sys.stderr,
        )
        return 1
    print("  ✓ scripts/run-swift-tests.sh enforces COMPOSE_REQUIRE_FFI=1 on macOS.")

    print("--- [validate-swift-parity] ComposeKit FFI wiring gate passed (TASK-01). ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
