.PHONY: build run test test-snapshots e2e hil hil-ble preflight preflight-unsigned package lint clean

build:
	cd app && swift build --product Buddygotchi && swift build --product BuddygotchiSignal

run:
	cd app && swift run Buddygotchi

test:
	@set -e; \
	DEVELOPER_DIR_VALUE="$${DEVELOPER_DIR:-$$(xcode-select -p 2>/dev/null || true)}"; \
	if [ -n "$$DEVELOPER_DIR_VALUE" ] && { \
		[ -d "$$DEVELOPER_DIR_VALUE/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule" ] || \
		[ -d "$$DEVELOPER_DIR_VALUE/Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule" ]; \
	}; then \
		cd app && swift test; \
	else \
		echo ""; \
		echo "============================================================" >&2; \
		echo "WARNING: XCTest unavailable - tests COMPILED but DID NOT RUN." >&2; \
		echo "Use the HTTP e2e suite (make e2e) or CI for verification." >&2; \
		echo "Set BUDDY_ALLOW_COMPILE_ONLY=1 to allow this compile-only check." >&2; \
		echo "============================================================" >&2; \
		echo ""; \
		BUILD_LOG="$$(mktemp -t buddygotchi-build-tests.XXXXXX)"; \
		set +e; \
		(cd app && swift build --build-tests) > "$$BUILD_LOG" 2>&1; \
		BUILD_STATUS="$$?"; \
		set -e; \
		cat "$$BUILD_LOG"; \
		if [ "$$BUILD_STATUS" -ne 0 ]; then \
			if grep -q "Linking BuddygotchiTests" "$$BUILD_LOG" && grep -q "link command failed" "$$BUILD_LOG"; then \
				echo "WARNING: swift build --build-tests reached the BuddygotchiTests link step; treating this CommandLineTools shim limitation as compile-verified." >&2; \
			else \
				rm -f "$$BUILD_LOG"; \
				exit "$$BUILD_STATUS"; \
			fi; \
		fi; \
		rm -f "$$BUILD_LOG"; \
		if [ "$${BUDDY_ALLOW_COMPILE_ONLY:-}" != "1" ]; then \
			exit 1; \
		fi; \
	fi

test-snapshots:
	mkdir -p /tmp/buddy-snapshots
	touch /tmp/buddy-snapshots/.enable
	cd app && swift test --disable-sandbox --filter SnapshotHarnessTests

e2e:
	app/tools/e2e-smoke.sh

hil:
	cd firmware/esp32 && python3 -m pytest tests/hil -m "not ble"

hil-ble:
	cd firmware/esp32 && python3 -m pytest tests/hil -m "ble"

package:
	app/tools/package.sh

preflight:
	app/tools/release-preflight.sh

preflight-unsigned:
	BUDDY_ALLOW_UNSIGNED=1 app/tools/release-preflight.sh

lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		cd app && swift-format lint -r Buddygotchi BuddygotchiSignal Tests; \
	else \
		echo "swift-format is not installed. Install it or run swift test for the required check."; \
		exit 1; \
	fi

clean:
	rm -rf app/.build .build
