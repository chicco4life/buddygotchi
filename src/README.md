# Buddygotchi Legacy Source Tree

The active Buddygotchi runtime is the Swift macOS app in `app/`.

This `src/` tree contains two different things:

- `outputs/esp32/`: active ESP32 firmware, PlatformIO project, hardware docs, and helper tools.
- `src/`, `schema/`, `tests/`, and `outputs/web/`: legacy Bun/TypeScript daemon and browser UI prototype retained for reference.

Do not treat the Bun daemon as the production path unless a task explicitly targets it.

## Legacy Bun Commands

```sh
bun install
bun run dev
bun test
```

The legacy daemon used port `8080`. The production Swift app uses `127.0.0.1:21321`.

## ESP32 Firmware

```sh
cd outputs/esp32
pio run
pio run -t upload
pio run -t uploadfs
```

See `outputs/esp32/README.md` and the root `ARCHITECTURE.md` for current hardware behavior.
