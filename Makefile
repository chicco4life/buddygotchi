.PHONY: build run test test-snapshots e2e hil hil-ble package lint clean

build:
	cd app && swift build

run:
	cd app && swift run Buddygotchi

test:
	cd app && swift test

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

lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		cd app && swift-format lint -r Buddygotchi BuddygotchiSignal Tests; \
	else \
		echo "swift-format is not installed. Install it or run swift test for the required check."; \
		exit 1; \
	fi

clean:
	rm -rf app/.build .build
