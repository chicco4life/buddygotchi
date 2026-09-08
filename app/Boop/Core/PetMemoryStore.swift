import Foundation

/// Persistence seam for `PetMemory`. The engine loads once at startup and
/// saves when the reducer's memory changes; injecting the store keeps tests
/// hermetic (no store → no disk I/O at all).
@MainActor
protocol PetMemoryStoring {
    func load() -> PetMemory?
    func save(_ memory: PetMemory)
}
