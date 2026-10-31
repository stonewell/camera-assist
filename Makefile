.PHONY: all rust-ios rust-ios-sim generate-bindings xcframework build-xcframework dev-camera-app dev-camera-clip test verify

all: rust-ios

rust-ios:
	./scripts/build-rust-ios.sh aarch64-apple-ios

rust-ios-sim:
	./scripts/build-rust-ios.sh aarch64-apple-ios-sim

generate-bindings:
	./scripts/generate-uniffi-bindings.sh

# TASK-01: ComposeKit links this XCFramework as a local binary target. Assembling it needs
# Xcode, so on non-Darwin hosts fail loudly instead of building a ComposeKit that cannot compile.
xcframework:
	@if [ "$$(uname -s)" != "Darwin" ]; then \
		echo "error: ComposeCore.xcframework can only be assembled on macOS with Xcode." >&2; \
		echo "       ComposeKit will NOT compile without it (no mock fallback)." >&2; \
		echo "       On Linux run 'make verify' for the structural parity gate instead." >&2; \
		exit 1; \
	fi
	./scripts/build-xcframework.sh

# Backwards-compatible alias; keep both entry points behaving identically.
build-xcframework: xcframework

dev-camera-app: xcframework
	cd apple/CameraApp && xtool dev build

dev-camera-clip:
	cd apple/CameraAppClip && xtool dev build

verify:
	./scripts/verify-all.sh

test: verify
