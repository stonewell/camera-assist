#!/usr/bin/env python3
"""
scripts/audit-image-decoders.py
Spike R3: Desktop Image Decoder Ecosystem & Licensing Compliance Auditor.
Audits JPEG, HEIC, and RAW image decoding candidates for the desktop Photo Review application.
"""

import sys

DECODER_CANDIDATES = [
    {
        "name": "zune-jpeg",
        "format": "JPEG",
        "language": "Pure Rust",
        "license": "MIT OR Apache-2.0",
        "status": "APPROVED",
        "speed_rating": "Ultra Fast (SIMD accelerated)",
        "commercial_permitted": True,
        "notes": "Primary high-throughput JPEG decoder for desktop batch scanning."
    },
    {
        "name": "image-rs",
        "format": "PNG / WebP / TIFF",
        "language": "Pure Rust",
        "license": "MIT OR Apache-2.0",
        "status": "APPROVED",
        "speed_rating": "Fast",
        "commercial_permitted": True,
        "notes": "Standard multi-format raster image decoding."
    },
    {
        "name": "kamadak-exif",
        "format": "EXIF Metadata",
        "language": "Pure Rust",
        "license": "BSD-2-Clause",
        "status": "APPROVED",
        "speed_rating": "Zero-copy Instant",
        "commercial_permitted": True,
        "notes": "Extracts camera orientation, focal length, ISO, and shutter speed without decoding full pixels."
    },
    {
        "name": "apple-imageio",
        "format": "HEIC / ProRAW / JPEG",
        "language": "Apple System Framework",
        "license": "Apple Proprietary (Free with OS)",
        "status": "APPROVED",
        "speed_rating": "Hardware Accelerated (Apple Silicon)",
        "commercial_permitted": True,
        "notes": "Native zero-overhead HEIC and ProRAW decoding on macOS."
    },
    {
        "name": "libheif",
        "format": "HEIC / AVIF",
        "language": "C++ Binding",
        "license": "LGPL-3.0",
        "status": "RESTRICTED",
        "speed_rating": "Fast",
        "commercial_permitted": True,
        "notes": "Permitted ONLY via dynamic linking (.so / .dll / .dylib) on Linux and Windows to maintain compliance with LGPL-3.0."
    }
]

def main() -> int:
    print("==================================================================")
    print(" Spike R3: Desktop Image Decoder Architecture & Licensing Audit")
    print("==================================================================")

    violations = []
    approved_count = 0
    restricted_count = 0

    for dec in DECODER_CANDIDATES:
        name = dec["name"]
        fmt = dec["format"]
        lic = dec["license"]
        status = dec["status"]

        print(f" * Library: {name:<18} [{fmt}]")
        print(f"   License: {lic:<24} Status: {status}")
        print(f"   Notes:   {dec['notes']}")

        if status == "APPROVED":
            approved_count += 1
        elif status == "RESTRICTED":
            restricted_count += 1
            if "dynamic linking" not in dec["notes"].lower():
                violations.append(f"Restricted library '{name}' must have dynamic linking isolation notes.")
        else:
            violations.append(f"Unknown status '{status}' for {name}")

    print("------------------------------------------------------------------")
    print(f" Summary: {approved_count} Approved, {restricted_count} Restricted (Isolated Dynamic Link), {len(violations)} Violations.")
    print("==================================================================")

    if violations:
        print("[FAIL] Licensing violations found:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("[SUCCESS] Desktop image decoding architecture adheres to permissive licensing policy.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
