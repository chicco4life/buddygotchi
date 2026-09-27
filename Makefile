# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
.PHONY: build run debug test eval tools faces fw flash sim fw-test e2e tools-test clean

PIO := firmware/tools/pio.sh

# Mac app, boop-hook, boopdev, in one `swift build`: building them one by
# one made SwiftPM redo their shared work each time (about 98 s from clean
# against 64 s, and 18 s against 2 s after a one-file change). A bare build
# also links the BoopTests runner, so its main is generated first.
# SWIFT_CHECK makes importing a target that isn't a declared dependency an
# error, not a warning, so app/ can't reach internal/ code (internal/README.md).
# internal/app/tools/test.py passes the same flag; change the two together.
SWIFT_CHECK := --explicit-target-dependency-import-check error
build:
	python3 internal/app/tools/gen-test-runner.py
	swift build $(SWIFT_CHECK)

# The Mac app with Bluetooth. The owner runs this, not agents. Builds
# everything first (the app copies the boop-hook built next to it), then
# starts the binary: `swift run` would check the build all over again.
run: build
	.build/debug/Boop

# The same, printing everything to this terminal as it happens: hooks, the
# core's decisions, device messages and every brain pass (HARNESS.md §8).
debug: build
	.build/debug/Boop --debug

# Swift unit tests through the XCTest shim (there's no Xcode here): one
# `swift build` of the whole package, as `build` does, then the runner.
test:
	python3 internal/app/tools/test.py

# The harness eval scenarios (plan/EVALS.md), each run 3 times against Jev.
# They need Jev's key in BOOP_JEV_KEY and fail without it
# (plan/VERIFICATION.md L5).
eval: build
	.build/debug/boopdev eval

# internal/tools/.venv with pyserial and Pillow, for boopctl.
# internal/tools/boopctl makes it by itself when it's missing; this also
# refreshes it after internal/tools/requirements.txt changes.
tools: internal/tools/.venv/.ok

internal/tools/.venv/.ok: internal/tools/requirements.txt
	python3 -m venv internal/tools/.venv
	internal/tools/.venv/bin/pip install --quiet --upgrade pip
	internal/tools/.venv/bin/pip install --quiet -r internal/tools/requirements.txt
	touch $@

# The device's faces, firmware/assets/faces.h, from the mood designs in
# internal/tools/facegen/design/svg/, checked against Chrome's drawing of
# them first. Rerun it when the designs change.
faces: tools
	internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check

# Firmware for the board (env cyd24).
fw:
	$(PIO) run -e cyd24

# Build and upload over USB (auto-reset, no BOOT press).
flash:
	$(PIO) run -e cyd24 -t upload $(if $(BOOP_PORT),--upload-port $(BOOP_PORT))

# Firmware unit tests on the Mac.
fw-test:
	$(PIO) test -e native

# Every device scenario in the simulator, against the goldens (L1). The
# PNGs land in /tmp/boop-sim/<scenario>/; internal/tools/boopctl sim NAME
# runs one.
sim:
	internal/tools/boopctl sim

# Hook → app → USB → device pipeline check (L4), on the board over USB.
e2e: build
	internal/tools/boopctl e2e

# The tools' own tests, with no board or camera: boopctl's commands, and the
# webcam recorder on synthetic video.
tools-test:
	internal/tools/boopctl --help > /dev/null
	internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests
	python3 -m unittest discover -s internal/tools/webcam/tests

clean:
	rm -rf .build firmware/.pio
