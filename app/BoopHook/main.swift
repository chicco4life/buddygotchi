import Darwin
import Foundation
import HookWire

// The hook client (ADAPTERS.md §2): `boop-hook claude|codex`. Reads the hook's
// JSON, keeps the fields Boop needs, writes one line to the app's socket and
// exits 0. It never prints, so it never answers for the agent, and it gives up
// quickly when the app isn't there.

let inputCap = 256 * 1024

// Whatever happens, finish within a second and report success.
signal(SIGALRM) { _ in _exit(0) }
signal(SIGPIPE, SIG_IGN)
alarm(1)

let started = Int64(Date().timeIntervalSince1970 * 1000)
let agent = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "claude"

var payload = Data()
var chunk = [UInt8](repeating: 0, count: 65536)
while true {
    let n = read(STDIN_FILENO, &chunk, chunk.count)
    if n <= 0 { break }
    // Past the cap the rest is drained and ignored.
    let room = inputCap - payload.count
    if room > 0 { payload.append(contentsOf: chunk[0..<min(n, room)]) }
}

if ["claude", "codex"].contains(agent),
   let line = HookLine.extract(agent: agent, payload: payload, ts: started, names: .live) {
    HookSocket.send(line.encoded(), to: HookSocket.defaultPath())
}
exit(0)
