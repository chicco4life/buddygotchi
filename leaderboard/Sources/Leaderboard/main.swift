import Foundation
import LeaderboardCore

@main struct Leaderboard {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var port = 8080, database = "leaderboard.sqlite", i = 0
        while i < args.count {
            guard i + 1 < args.count else { throw Usage.invalidArguments }
            switch args[i] {
            case "--port": guard let value = Int(args[i + 1]), (1...65535).contains(value) else { throw Usage.invalidArguments }; port = value
            case "--database": database = args[i + 1]
            default: throw Usage.invalidArguments
            }
            i += 2
        }
        try await runLeaderboard(port: port, database: database)
    }
    enum Usage: Error { case invalidArguments }
}
