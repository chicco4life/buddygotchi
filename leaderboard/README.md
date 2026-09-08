# Boop leaderboard

A Swift 6 service with Hummingbird 2 and SQLite. No accounts, access logging,
IP persistence, or activity data. It stores only buddy names, silhouettes,
public device identities, signed daily totals, and their verification metadata.

```sh
swift run leaderboard --port 8080
# Optional durable database location:
swift run -c release leaderboard --port 8080 --database /data/leaderboard.sqlite
swift test # full Xcode on macOS; standard Swift toolchain on Linux
# Command Line Tools only (no XCTest):
swift run LeaderboardTests
```

Run on a macOS 14+ or Linux host with Swift 6. Linux requires SQLite and OpenSSL
headers/libraries (`apt install libsqlite3-dev libssl-dev pkg-config`). macOS
uses system CryptoKit. Linux uses system libcrypto (OpenSSL 1.1.1 or 3); neither
adds a Swift package dependency. Hummingbird is the sole package dependency.
Build a release binary for the deployment host, run under its service manager,
and mount persistent storage for the database and WAL. Put HTTPS in front of
port 8080. Disable proxy access logs if you want the same no-IP-retention policy.
`GET /healthz` returns `ok`. Back up SQLite using its online backup facilities.

Set the app's Leaderboard URL to the service base URL and explicitly opt in.
Empty URL disables leaderboard networking. Software-only buddies cannot rank.

`POST /submit` accepts exactly these keys:
`buddyName`, `silhouette`, `xpTotal`, `signatures`, `unit`, `pub`, `alg`.
Each signature has exactly `day`, `xp`, `nonce`, `sig`. Public keys are base64
SEC1 uncompressed P-256 points; unit is the first eight SHA-256 bytes in lowercase
hex. DER ECDSA signatures cover ASCII `unit|day|xp|nonce` with SHA-256.
Every signature and the final total must verify. Invalid bodies return 400;
replays and non-increasing day histories or decreasing totals return 409.
A failed batch rolls back completely. Successful submissions return 201.
The device signs a host-supplied total: this is not proof of independently
measured activity or a manufacturer certificate.

`GET /rank?unit=<hex16>&view=all|month|friends&code=<hex6>&friends=<JSON-array>`
returns `view`, optional `rank`, and up to 100 `entries`. Your rank is calculated
across the entire selected view. Scores descend, ties use unit ID ascending.
All-time uses the latest signed lifetime total. Month subtracts the last signed
total before the current UTC month; a new unit has baseline zero. Signed days
are owner-local labels, so tomorrow's UTC date is allowed for time-zone skew.
Friends includes yourself and units whose six-character uppercase hex code
matches a locally supplied code. Codes are the first six unit characters;
collisions include all matching units. Friends lists are never persisted.

The app stores one signature per local day. It sends unsent signatures and the
latest signed total in that batch (up to 400 days per submission), reserves at most one submission attempt per local day
(including network failures), and retains unsent signatures for the next day.
A response lost after acceptance can cause a replay conflict; this minimal
protocol deliberately rejects duplicates instead of silently accepting them.

Socket e2e: launch a **fresh, named software-only headless buddy** with
`BOOP_TEST_SIGNER=1 app/tools/headless.sh`, then run `app/tools/e2e-smoke.sh`.
The smoke runner builds and starts an isolated service on a random port,
uses `/state/sign`, submits, checks exact key sets and all three rank views,
then stops its service and restores URL/opt-in settings. Run with a fresh
store for each e2e run: daily submission limits persist. The clearly named
`TestDeviceSigner` is available only with headless mode and that environment
flag; it cannot replace a recorded hardware identity.
