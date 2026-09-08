import Foundation

@MainActor
protocol OutputProvider {
    var id: String { get }
    func start(engine: BuddyEngine) async
    func stop() async
    func stateDidChange(prev: BuddyState, next: BuddyState)
}
