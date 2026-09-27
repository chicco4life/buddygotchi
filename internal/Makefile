# Boop's development targets: tests, the simulator and the device tools.
# Run them as `make -C internal <target>` from the repo root. Every recipe
# runs from the repo root, so the paths below are the same as in the root
# Makefile. See plan/VERIFICATION.md §2.
.PHONY: test tools faces fw fw-test sim e2e tools-test

ROOT := $(abspath ..)
PIO := firmware/tools/pio.sh

# Swift unit tests through the XCTest shim (there's no Xcode here): one
# `swift build` of the whole package, as `build` does, then the runner.
test:
	cd $(ROOT) && python3 internal/app/tools/test.py

# internal/tools/.venv with pyserial, Pillow and Textual, for boopctl.
# internal/tools/boopctl makes it by itself when it's missing; this also
# refreshes it after internal/tools/requirements.txt changes.
tools: tools/.venv/.ok

tools/.venv/.ok: tools/requirements.txt
	cd $(ROOT) && python3 -m venv internal/tools/.venv
	cd $(ROOT) && internal/tools/.venv/bin/pip install --quiet --upgrade pip
	cd $(ROOT) && internal/tools/.venv/bin/pip install --quiet -r internal/tools/requirements.txt
	touch $@

# The device's faces, firmware/assets/faces.h, from the mood designs in
# internal/tools/facegen/design/svg/, checked against Chrome's drawing of
# them first. Rerun it when the designs change.
faces: tools
	cd $(ROOT) && internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check

# Firmware for the board (env cyd24).
fw:
	cd $(ROOT) && $(PIO) run -e cyd24

# Firmware unit tests on the Mac.
fw-test:
	cd $(ROOT) && $(PIO) test -e native

# Every device scenario in the simulator, against the goldens (L1). The
# PNGs land in /tmp/boop-sim/<scenario>/; internal/tools/boopctl sim NAME
# runs one.
sim:
	cd $(ROOT) && internal/tools/boopctl sim

# Hook → app → USB → device pipeline check (L4), on the board over USB.
e2e:
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && internal/tools/boopctl e2e

# The tools' own tests, with no board or camera: boopctl's commands, and the
# webcam recorder on synthetic video.
tools-test: tools
	cd $(ROOT) && internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/tools/webcam/tests
