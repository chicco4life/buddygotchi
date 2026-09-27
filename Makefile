# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
# The development targets (tests, simulator, tools) are in internal/Makefile:
# make -C internal <target>.
.PHONY: build run debug dash day flash eval clean

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
# core's decisions, device messages and every brain pass (plan/harness/HARNESS.md).
debug: build
	.build/debug/Boop --debug

# The live dashboard for the app `make debug` started (plan/DASHBOARD.md).
# Run it in a second terminal.
dash:
	internal/tools/boopctl dash

# What Boop did in a day, and why, by the hour, from the logs `make debug`
# leaves (plan/harness/HARNESS.md §9). DATE=YYYY-MM-DD picks the day; the
# newest line's by default.
day:
	internal/tools/boopctl day $(if $(DATE),--date $(DATE))

# The harness eval scenarios (plan/EVALS.md), each run 3 times against Jev.
# They need Jev's key in BOOP_JEV_KEY and fail without it
# (plan/VERIFICATION.md L5).
eval: build
	.build/debug/boopdev eval

# Build and upload over USB (auto-reset, no BOOT press).
flash:
	$(PIO) run -e cyd24 -t upload $(if $(BOOP_PORT),--upload-port $(BOOP_PORT))

clean:
	rm -rf .build firmware/.pio
