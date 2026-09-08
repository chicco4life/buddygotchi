import Foundation
import LeaderboardWire

enum LeaderboardError: Error, CustomStringConvertible {
    case cancelled, invalidSignature, unavailable(String), rejected(Int), identityChanged, replay
    var description: String {
        switch self {
        case .cancelled: return "cancelled"
        case .invalidSignature: return "invalid signature"
        case .unavailable(let why): return "unavailable: \(why)"
        case .rejected(let code): return "rejected: \(code)"
        case .identityChanged: return "identity changed"
        case .replay: return "replay"
        }
    }
}
struct LeaderboardClient: Sendable {
    var url: URL
    var session: URLSession = .shared
    func submit(_ body: LeaderboardSubmission) async throws {
        var request = URLRequest(url: url.appendingPathComponent("submit"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw LeaderboardError.unavailable("service http \(String(describing: (response as? HTTPURLResponse)?.statusCode))") }
    }
    func rank(unit: String, view: RankView, code: String, friends: [String]) async throws -> LeaderboardSnapshot {
        var parts = URLComponents(url: url.appendingPathComponent("rank"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "unit", value: unit), .init(name: "view", value: view.rawValue), .init(name: "code", value: code),
                            .init(name: "friends", value: String(decoding: try JSONEncoder().encode(friends), as: UTF8.self))]
        let (data, response) = try await session.data(from: parts.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LeaderboardError.unavailable("service http \(String(describing: (response as? HTTPURLResponse)?.statusCode))") }
        return try JSONDecoder().decode(LeaderboardSnapshot.self, from: data)
    }
}
