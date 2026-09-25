# Remove the persistent Last finished row — 2026-09-11

Removed the text below the device's working count and its bottom-screen history
shortcut. Normal face taps still open task details, whose Next control reaches
recent history. Temporary completion notices remain unchanged. The wire fields
and retained history are unchanged.

Both normal and USB-only firmware builds passed. A reserved USB-only run passed
all 29 dashboard/scope checks, including three new idle/working/done comparisons
proving recent history does not add pixels to the bottom 35-pixel band. Navigation
checks cover the removed shortcut, history paging and direct exit.

Five scenes were independently captured twice with identical hashes and fresh
timestamps. History and completion-notice goldens matched the existing references
at zero error. The three affected face/scope goldens changed only within
`(25,256)–(278,269)`, exactly the removed text region; these references were updated
and checked against the second captures at zero error. See `captures.json`,
`diff-bounds.json`, `tests.xml` and the PNGs in this directory.

The test reservation restored its full 16 MB original flash backup. After visual
review, the verified normal build was installed under a new device reservation,
with automatic rollback available on failed startup. It reconnected to the
existing GUI and reached 66 seconds of uptime with the original panic count
unchanged at 103, safe mode off, RTC synced, and `usbOnly=false`. The normal
firmware is intentionally left installed to fulfill the requested device change.
This bounded check does not resolve the earlier intermittent startup finding.

`installed.json` and `firmware-images.json` identify the exact binary by SHA-256;
the embedded development git label alone does not identify uncommitted changes.
Settings/history were restored before installing, and the install did not erase
NVS or the filesystem. No webcam was used. Full backup and raw logs remain in
`/tmp/boop-remove-footer`.
