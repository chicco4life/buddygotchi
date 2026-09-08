import Foundation
import CoreFoundation
import LeaderboardWire

/// JSONDecoder coerces 200.0 to Int. This narrow decoder preserves JSON's
/// numeric types and feeds the shared DTO's Decodable validation in one parse.
enum SubmissionDecoder {
    static func decode(_ data: Data) throws -> LeaderboardSubmission {
        try LeaderboardSubmission(from: ObjectDecoder(value: JSONSerialization.jsonObject(with: data)))
    }
}
private func integerValue(_ value: Any) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          !["d", "f"].contains(String(cString: number.objCType)) else { return nil }
    return Int(number.stringValue)
}
private struct ObjectDecoder: Decoder {
    let value: Any
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    func invalid() -> DecodingError { .dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid submission field type")) }
    func container<Key: CodingKey>(keyedBy: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard let object = value as? [String: Any] else { throw invalid() }
        return KeyedDecodingContainer(ObjectContainer<Key>(object: object, decoder: self))
    }
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer { throw invalid() }
    func singleValueContainer() throws -> any SingleValueDecodingContainer { throw invalid() }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == String.self, let string = value as? String { return string as! T }
        if type == Int.self, let integer = integerValue(value) { return integer as! T }
        if type == [SubmittedSignature].self, let array = value as? [Any] {
            return try array.enumerated().map { index, value in
                try SubmittedSignature(from: ObjectDecoder(value: value, codingPath: codingPath + [IndexKey(index: index)]))
            } as! T
        }
        throw invalid()
    }
}
private struct IndexKey: CodingKey {
    let index: Int
    var stringValue: String { String(index) }
    var intValue: Int? { index }
    init(index: Int) { self.index = index }
    init?(stringValue: String) { return nil }
    init?(intValue: Int) { index = intValue }
}
private struct ObjectContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: [String: Any]
    let decoder: ObjectDecoder
    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] { object.keys.compactMap(Key.init(stringValue:)) }
    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }
    func decodeNil(forKey key: Key) throws -> Bool { object[key.stringValue] is NSNull }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let value = object[key.stringValue] else { throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing field")) }
        return try ObjectDecoder(value: value, codingPath: codingPath + [key]).decode(type)
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> { throw decoder.invalid() }
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { throw decoder.invalid() }
    func superDecoder() throws -> any Decoder { throw decoder.invalid() }
    func superDecoder(forKey key: Key) throws -> any Decoder { throw decoder.invalid() }
}
