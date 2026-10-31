.PHONY: all rust-ios rust-ios-sim generate-bindings build-xcframework dev-camera-app dev-camera-clip test verify

all: rust-ios

rust-ios:
	./scripts/build-rust-ios.sh aarch64-apple-ios

rust-ios-sim:
	./scripts/build-rust-ios.sh aarch64-apple-ios-sim

generate-bindings:
	./scripts/generate-uniffi-bindings.sh

build-xcframework:
	./scripts/build-xcframework.sh

dev-camera-app:
	cd apple/CameraApp && xtool dev build

dev-camera-clip:
	cd apple/CameraAppClip && xtool dev build

verify:
	./scripts/verify-all.sh

test: verify
