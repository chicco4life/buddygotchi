# Boop v1. Run from the repo root. See README.md and plan/VERIFICATION.md.
# The development targets (tests, simulator, tools) are in internal/Makefile:
# make -C internal <target>.
.PHONY: build app run debug dash day flash eval clean

PIO := firmware/tools/pio.sh

# The whole package in one `swift build`: the Mac app, boopdev and the
# BoopTests runner, whose main is generated first; then agent-hooks' hook
# client, agent-hook, which the app copies from next to it, and JHarness'
# tools, jharness-emit and beacon (jharness/README.md).
# SWIFT_CHECK makes importing a target that isn't a declared dependency an
# error, not a warning, so app/ can't reach internal/ code (internal/README.md).
# `make -C internal test` runs this target, then the tests.
SWIFT_CHECK := --explicit-target-dependency-import-check error
build:
	python3 internal/app/tools/gen-test-runner.py
	swift build $(SWIFT_CHECK)
	swift build $(SWIFT_CHECK) --product agent-hook
	swift build $(SWIFT_CHECK) --product jharness-emit
	swift build $(SWIFT_CHECK) --product beacon

# The Mac app, the agent-hook it copies from next to it and boopdev, without
# the tests' generated runner, which is most of `build`'s time after a
# change to what BoopKit declares.
app:
	swift build $(SWIFT_CHECK) --product Boop
	swift build $(SWIFT_CHECK) --product agent-hook
	swift build $(SWIFT_CHECK) --product boopdev  # the doctor skill checks the hooks with it

# The Mac app with Bluetooth. The owner runs this, not agents. Builds the
# app, then starts the binary: `swift run` would check the build all over
# again.
run: app
	.build/debug/Boop

# The same, printing everything to this terminal as it happens: hooks, the
# core's decisions, device messages and every brain pass (plan/harness/HARNESS.md).
debug: app
	.build/debug/Boop --debug

# The live dashboard for the app `make debug` started.
# Run it in a second terminal.
dash:
	internal/tools/boopctl dash

# What Boop did in a day, and why, by the hour, from the logs `make debug`
# leaves (plan/harness/HARNESS.md §9). DATE=YYYY-MM-DD picks the day; the
# newest line's by default.
day:
	internal/tools/boopctl day $(if $(DATE),--date $(DATE))

# The harness eval scenarios (plan/EVALS.md) against Jev, all of them with no
# request budget: the final pass (plan/EVALS.md §2 counts its requests).
# While developing, run .build/debug/boopdev eval --only TEXT instead.
# They need Jev's key in BOOP_JEV_KEY and fail without it
# (plan/VERIFICATION.md L5).
eval: build
	.build/debug/boopdev eval --no-budget

# Build and upload over USB (auto-reset, no BOOT press).
flash:
	$(PIO) run -e cyd24 -t upload $(if $(BOOP_PORT),--upload-port $(BOOP_PORT))

clean:
	rm -rf .build firmware/.pio
