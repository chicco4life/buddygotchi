.PHONY: headless doctor build run test test-snapshots e2e hil hil-ble preflight preflight-unsigned package lint clean

build:
	cd app && swift build --product Boop && swift build --product BoopSignal

run:
	cd app && swift run Boop

test:
	python3 app/tools/test.py

test-snapshots:
	mkdir -p /tmp/buddy-snapshots
	touch /tmp/buddy-snapshots/.enable
	cd app && swift test --disable-sandbox --filter SnapshotHarnessTests

headless:
	app/tools/headless.sh

doctor:
	skills/doctor/doctor.sh --headless

e2e:
	@bash app/tools/e2e-headless.sh

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
		cd app && swift-format lint -r Boop BoopSignal Tests; \
	else \
		echo "swift-format is not installed. Install it or run swift test for the required check."; \
		exit 1; \
	fi

clean:
	rm -rf app/.build .build

.PHONY: webcam webcam-test
webcam:
	tools/webcam/webcam.sh $(ARGS)

webcam-test:
	python3 -m unittest discover -s tools/webcam/tests -v
