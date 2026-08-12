import Foundation

/// Persistence seam for `PetMemory`. The engine loads once at startup and
/// saves when the reducer's memory changes; injecting the store keeps tests
/// hermetic (no store → no disk I/O at all).
@MainActor
protocol PetMemoryStoring {
    func load() -> PetMemory?
    func save(_ memory: PetMemory)
}

/// JSON file in the Boop state dir (~/.boop/pet-memory.json). A file rather
/// than UserDefaults: it grows (agent identities, later keepsakes), and a
/// corrupt or unreadable file must cost us the memory, never the launch.
@MainActor
final class FilePetMemoryStore: PetMemoryStoring {
    private let url: URL

    init(stateDir: String) {
        self.url = URL(fileURLWithPath: stateDir).appendingPathComponent("pet-memory.json")
    }

    func load() -> PetMemory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PetMemory.self, from: data)
    }

    func save(_ memory: PetMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
