import Foundation
import CSQLite

struct StoreError: Error, Sendable { var message: String }
/// Owned exclusively by Store. Statements never escape the actor.
final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            sqlite3_close(handle); handle = nil; throw StoreError(message: message)
        }
        sqlite3_busy_timeout(handle, 5000)
    }
    private var statements: [String: OpaquePointer] = [:]
    deinit { for statement in statements.values { sqlite3_finalize(statement) }; sqlite3_close(handle) }
    @discardableResult func run(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        let statement: OpaquePointer
        if let cached = statements[sql] { statement = cached }
        else {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else { throw failure() }
            statement = prepared; statements[sql] = prepared
        }
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        for (index, value) in values.enumerated() {
            let rc = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard rc == SQLITE_OK else { throw failure() }
        }
        var rows: [[String]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
                })
            case SQLITE_DONE: return rows
            default: throw failure()
            }
        }
    }
    private func failure() -> StoreError { StoreError(message: String(cString: sqlite3_errmsg(handle))) }
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do { let result = try operation(); try run("COMMIT"); return result }
        catch { _ = try? run("ROLLBACK"); throw error }
    }
}
