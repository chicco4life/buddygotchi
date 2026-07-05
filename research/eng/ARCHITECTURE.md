# Architecture

Boop's architecture documentation is split by product surface. This file is a
short index for readers looking for the current architecture entry points; the
detailed docs are maintained as standalone files so the app/firmware runtime and
landing page can evolve independently.

- [ARCHITECTURE-APP.md](ARCHITECTURE-APP.md): Swift macOS app plus ESP32 firmware architecture, including hooks, state flow, outputs, firmware heartbeat, and test/mocking strategy.
- [ARCHITECTURE-LANDING.md](ARCHITECTURE-LANDING.md): landing page architecture, build/deploy shape, and boundaries from the native app.

Production boundary: `agent hooks -> HookServer -> BuddyEngine -> pure reducer -> OutputProvider`

Verification and release gates live in [TESTING.md](TESTING.md) and [RELEASE.md](RELEASE.md).
