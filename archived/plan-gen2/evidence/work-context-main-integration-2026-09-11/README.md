# Work scope integration with main

Integrated the shared English companion pipeline with main's completion notices
and tap-to-view task pages. Scope renders above the calm face at (24,24), width
W−48, leaving working-count and last-finished footers unchanged. Task pages,
completion notices and higher-priority layers cover it.

- `make test build`: 369 passed, zero skipped; Boop and BoopSignal built.
- Shipping and USB-only Waveshare firmware builds passed.
- Reserved USB-only run: 26 scope and dashboard interaction checks passed.
- No local-model quality, native editor or production BLE pass is implied.
  The earlier model coverage and timeout limitations remain.

The pre-integration evidence remains unchanged in the sibling work-context folder.
The six historical `scope-dashboard-*`/`scope-face-*`/`scope-idle-*` fixture names
now describe the calm face with different activity/footer contexts. Korean
fixtures test UTF-8 rendering; generated companion text remains English-only.

All six updated scope goldens were independently recaptured and matched at
zero error; capture timestamps were ordered and SHA-256 digests matched.
See [checks](usb-checks.txt) and [capture hashes](capture-sha256.txt).

The reservation restored the exact previous normal firmware/settings;
`usbOnly` is false and firmware identity matches the backup.
See [run result](usb-result.json) and [restored device](restored-normal.json).
