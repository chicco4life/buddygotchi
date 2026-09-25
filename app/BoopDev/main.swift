import BoopKit
import Foundation

// Developer CLI. Subcommands (replay, talk, brain, memory) arrive with the
// milestones that need them.
let usage = "usage: boopdev <replay|talk|brain|memory> …  (boop \(BoopVersion.current))"
FileHandle.standardError.write(Data((usage + "\n").utf8))
exit(CommandLine.arguments.count > 1 ? 2 : 0)
