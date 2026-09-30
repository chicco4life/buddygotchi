# Boop's development targets: tests, the simulator and the device tools.
# Run them as `make -C internal <target>` from the repo root. Every recipe
# runs from the repo root, so the paths below are the same as in the root
# Makefile. See plan/VERIFICATION.md §2.
.PHONY: test tools voice faces fw fw-test sim e2e tools-test

ROOT := $(abspath ..)
PIO := firmware/tools/pio.sh

# Swift unit tests through the XCTest shim (there's no Xcode here): the
# root `build` (one `swift build` of the whole package, the tests' runner
# included), then the runner. Then agent-hooks' own tests, which use Swift
# Testing and so run under `swift test`, in a build folder of their own.
test: voice
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && .build/debug/BoopTests
	cd $(ROOT)/agent-hooks && swift test --scratch-path .build/tests

# The voice pack, .build/voice/voice.bin, which the board plays from its SD
# card and the simulator and tests read from here (plan/VOICE.md §8), and
# app/BoopKit/Voice/Takes.swift, from the recorded voice bank. Rebuilt when
# the bank or voicegen changes. `voicegen.py --card /Volumes/CARD` also
# copies it onto a card.
voice: $(ROOT)/.build/voice/voice.bin

$(ROOT)/.build/voice/voice.bin: boop-design/assets/boop-voice-v1/manifest.json boop-design/assets/boop-voice-v1/dictionary.json tools/voicegen/voicegen.py
	cd $(ROOT) && python3 internal/tools/voicegen/voicegen.py

# internal/tools/.venv with pyserial, Pillow and Textual, for boopctl.
# internal/tools/boopctl makes it through this when it's missing; this also
# refreshes it after internal/tools/requirements.txt changes. A venv that
# already works (a worktree's may be a link to the main checkout's) is
# kept, and only its packages brought up to date.
tools: tools/.venv/.ok

tools/.venv/.ok: tools/requirements.txt
	cd $(ROOT) && test -x internal/tools/.venv/bin/python || { python3 -m venv internal/tools/.venv \
	  && internal/tools/.venv/bin/pip install --quiet --upgrade pip; }
	cd $(ROOT) && internal/tools/.venv/bin/pip install --quiet -r internal/tools/requirements.txt
	touch $@

# The device's faces, firmware/assets/faces.h, from the animation bank's
# designs (internal/boop-design/boop-sound-bank-v4/, which facegen runs with
# node), checked against Chrome's drawing of them first. Rerun it when the
# bank changes, then its sounds: node internal/tools/sfxgen/sfxgen.mjs.
faces: tools
	cd $(ROOT) && internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check

# Firmware for the board (env cyd24).
fw:
	cd $(ROOT) && $(PIO) run -e cyd24

# Firmware unit tests on the Mac.
fw-test: voice
	cd $(ROOT) && $(PIO) test -e native

# Every device scenario in the simulator, against the goldens (L1). The
# PNGs land in /tmp/boop-sim/<scenario>/; internal/tools/boopctl sim NAME
# runs one.
sim: voice
	cd $(ROOT) && internal/tools/boopctl sim

# Hook → app → USB → device pipeline check (L4), on the board over USB.
e2e:
	$(MAKE) -C $(ROOT) build
	cd $(ROOT) && internal/tools/boopctl e2e

# The tools' own tests, with no board or camera: boopctl's commands (the
# working day's script and report among them, and the takes they read from
# the voice pack), and the webcam recorder on synthetic video.
tools-test: tools voice
	cd $(ROOT) && internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests
	cd $(ROOT) && python3 -m unittest discover -s internal/tools/webcam/tests
