# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
.PHONY: build run test eval tools fw flash sim fw-test e2e webcam webcam-test clean

PIO := firmware/tools/pio.sh

# Mac app, boop-hook, boopdev. By product: a bare `swift build` also links
# the BoopTests runner, which has no main until `make test` generates one.
build:
	cd app && swift build --product Boop && swift build --product boop-hook && swift build --product boopdev

# The Mac app with Bluetooth. The owner runs this, not agents. Builds
# everything first: the app copies the boop-hook built next to it, and
# `swift run Boop` alone doesn't build boop-hook. `make run DEBUG_LOG=FILE`
# also writes the brain's debug log, to follow with `boopdev watch FILE`.
run: build
	cd app && swift run Boop $(if $(DEBUG_LOG),--debug-log $(abspath $(DEBUG_LOG)))

# Swift unit tests through the XCTest shim (there's no Xcode here).
test:
	python3 app/tools/test.py

# The harness eval scenarios: rules classifier, no writer (plan/EVALS.md).
eval:
	cd app && swift build --product boopdev
	app/.build/debug/boopdev eval

# tools/.venv with pyserial and Pillow, for boopctl.
tools: tools/.venv/.ok

tools/.venv/.ok: tools/requirements.txt
	python3 -m venv tools/.venv
	tools/.venv/bin/pip install --quiet --upgrade pip
	tools/.venv/bin/pip install --quiet -r tools/requirements.txt
	touch $@

# Firmware for the board (env cyd24).
fw:
	$(PIO) run -e cyd24

# Build and upload over USB (auto-reset, no BOOT press).
flash:
	$(PIO) run -e cyd24 -t upload $(if $(BOOP_PORT),--upload-port $(BOOP_PORT))

# Firmware unit tests on the Mac.
fw-test:
	$(PIO) test -e native

# The renderer simulator, boop-sim (runs scenarios via tools/boopctl sim).
sim:
	$(PIO) run -e native

# Hook → app → USB → device pipeline check (built in J1).
e2e:
	$(MAKE) build
	tools/boopctl e2e

# The opt-in webcam recorder (tools/webcam/README.md): make webcam ARGS='list'.
webcam:
	tools/webcam/webcam.sh $(ARGS)

# The recorder's own tests, on synthetic video. They never open a camera.
webcam-test:
	python3 -m unittest discover -s tools/webcam/tests -v

clean:
	rm -rf app/.build firmware/.pio
