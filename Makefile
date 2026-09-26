# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
.PHONY: build sign run debug test eval tools fw flash sim fw-test e2e webcam webcam-test clean

PIO := firmware/tools/pio.sh

# Mac app, boop-hook, boopdev, in one `swift build`: building them one by
# one made SwiftPM redo their shared work each time (about 98 s from clean
# against 64 s, and 18 s against 2 s after a one-file change). A bare build
# also links the BoopTests runner, so its main is generated first.
build:
	python3 app/tools/gen-test-runner.py
	cd app && swift build
	@$(MAKE) --no-print-directory sign

# Re-signs the Mac app with the owner's self-signed "Boop Dev" certificate
# when the login keychain has one. An ad-hoc signature changes with every
# build, so the Keychain would ask for the Jev key again after each rebuild;
# a certificate gives the app one identity it can remember. Without the
# certificate the build stays ad-hoc signed. Set SIGN_IDENTITY to use another.
SIGN_IDENTITY ?= Boop Dev
sign:
	@if security find-identity -p codesigning | grep -q '"$(SIGN_IDENTITY)"'; then \
		codesign -f -s "$(SIGN_IDENTITY)" --identifier com.boopcomputer.boop app/.build/debug/Boop \
			&& echo "signed Boop as $(SIGN_IDENTITY)"; \
	fi

# The Mac app with Bluetooth. The owner runs this, not agents. Builds
# everything first (the app copies the boop-hook built next to it), then
# starts the binary: `swift run` would check the build all over again.
run: build
	app/.build/debug/Boop

# The same, printing everything to this terminal as it happens: hooks, the
# core's decisions, device messages and every brain pass (HARNESS.md §8).
debug: build
	app/.build/debug/Boop --debug

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
