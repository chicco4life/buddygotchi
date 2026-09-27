import Foundation

/// Why a change was refused: a bad name at setup, or a hook the installer
/// won't touch. For the log or the person.
public struct Refusal: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}
