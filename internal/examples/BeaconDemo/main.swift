import Beacon
import BrainKit
import Foundation

// `beacon`: the brain kit's second example (plan/kit/BRAIN-KIT.md §11).
//   beacon [--steering DIR]                  the worked example's run: every event the log wrote, and every prompt
//   beacon listen --socket PATH [--steering DIR]
//                                            Beacon live, taking events from `kit-emit` on PATH, the demo brain
//                                            answering; prints each line and pass as it happens. Ctrl-C stops it.

let args = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
if args.contains("--help") || args.contains("-h") {
    print("""
        usage: beacon [--steering DIR]
               beacon listen --socket PATH [--steering DIR]
        The brain kit's second example (plan/kit/BRAIN-KIT.md §11). With no command it runs the worked
        example on a virtual clock and prints every event the log wrote and every prompt the brain was sent.
        listen runs Beacon live on the socket at PATH, which kit-emit sends events to, e.g.
          kit-emit --socket PATH ci build_failed branch=main run=812
        and prints each line and pass as it happens, until Ctrl-C.
        --steering is Beacon's folder, internal/examples/Beacon/steering from the repo root by default.
        """)
    exit(0)
}
let steering = URL(fileURLWithPath: value("--steering") ?? "internal/examples/Beacon/steering")
guard FileManager.default.fileExists(atPath: steering.appendingPathComponent("guide.md").path) else {
    FileHandle.standardError.write(Data("beacon: no steering in \(steering.path): run it from the repo root, or pass --steering\n".utf8))
    exit(2)
}

if args.first == "listen" {
    guard let path = value("--socket") else {
        FileHandle.standardError.write(Data("beacon: listen needs --socket PATH\n".utf8))
        exit(2)
    }
    setvbuf(stdout, nil, _IOLBF, 0)
    let running = try Beacon.listen(socket: path, steering: steering) { print($0) }
    print("beacon: listening on \(path)")
    signal(SIGINT) { _ in exit(0) }
    withExtendedLifetime(running) { dispatchMain() }
}

let run = try await Beacon.demo(steering: steering)
print("THE LOG")
run.log.forEach { print($0) }
for (i, p) in run.prompts.enumerated() {
    print("\nPROMPT \(i + 1)\n" + p.prompt)
}
