#!/usr/bin/env python3
"""
scripts/audit-models.py
Desktop ONNX Model Compliance and License Auditor for Camera Assist / Photo Review.
Ensures zero GPL/AGPL or non-commercial models enter the approved production distribution.
"""

import json
import sys
from pathlib import Path

def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    manifest_path = repo_root / "shared" / "models" / "models.json"

    if not manifest_path.is_file():
        print(f"[ERROR] Model manifest not found: {manifest_path}", file=sys.stderr)
        return 1

    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[ERROR] Failed to parse {manifest_path}: {e}", file=sys.stderr)
        return 1

    policy = data.get("audit_policy", {})
    allowed_licenses = set(policy.get("allowed_licenses", []))
    prohibited_licenses = set(policy.get("prohibited_licenses", []))
    models = data.get("models", [])

    print("==================================================================")
    print(" Camera Assist Desktop ONNX Model License & Architecture Audit")
    print("==================================================================")
    print(f" Manifest:            {manifest_path.relative_to(repo_root)}")
    print(f" Allowed Licenses:    {', '.join(sorted(allowed_licenses))}")
    print(f" Prohibited Licenses: {', '.join(sorted(prohibited_licenses))}")
    print("------------------------------------------------------------------")

    violations = []
    approved_count = 0
    rejected_count = 0

    for m in models:
        mid = m.get("id", "unknown")
        name = m.get("name", mid)
        lic = m.get("license", "unknown")
        status = m.get("status", "unknown")
        task = m.get("task", "unknown")
        commercial = m.get("commercial_use_permitted", False)

        print(f" * Model: {name:<26} [{mid}]")
        print(f"   Task: {task:<18} License: {lic:<12} Status: {status}")

        if status == "approved":
            if lic not in allowed_licenses:
                violations.append(
                    f"Model '{mid}' is marked APPROVED but has unapproved license '{lic}'!"
                )
            if not commercial:
                violations.append(
                    f"Model '{mid}' is marked APPROVED but commercial_use_permitted is False!"
                )
            approved_count += 1
        elif status == "rejected":
            if "rejection_reason" not in m:
                violations.append(
                    f"Model '{mid}' is REJECTED but missing 'rejection_reason' explanation."
                )
            replacement = m.get("replacement_id")
            if not replacement:
                violations.append(
                    f"Model '{mid}' is REJECTED but missing approved 'replacement_id'."
                )
            print(f"   Reason: {m.get('rejection_reason', 'N/A')}")
            print(f"   Replacement: {replacement}")
            rejected_count += 1
        else:
            violations.append(f"Model '{mid}' has unrecognized status '{status}'!")

    print("------------------------------------------------------------------")
    print(f" Audit Summary: {approved_count} approved, {rejected_count} rejected, {len(violations)} violations.")
    print("==================================================================")

    if violations:
        print("[FAIL] Audit discovered license compliance violations:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("[SUCCESS] All desktop models comply with open-source and commercial licensing policy.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
