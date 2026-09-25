# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
.PHONY: build run test tools fw flash sim fw-test e2e clean

PIO := firmware/tools/pio.sh

# Mac app, boop-hook, boopdev.
build:
	cd app && swift build

# The Mac app with Bluetooth. The owner runs this, not agents.
run:
	cd app && swift run Boop

# Swift unit tests through the XCTest shim (there's no Xcode here).
test:
	python3 app/tools/test.py

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

clean:
	rm -rf app/.build firmware/.pio
