import Foundation
import CSQLite

/// Access from one owner actor; every snapshot is saved in one SQLite transaction.
public final class JobStore {
    private var db: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw DownloadError.storage("Cannot open database") }
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> DownloadError { .storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable") }
    public func load() throws -> [DownloadJob] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM jobs ORDER BY rowid", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var jobs = [DownloadJob]()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            var job = try JSONDecoder().decode(DownloadJob.self, from: Data(String(cString: text).utf8))
            // A crash must never leave a phantom running task.
            if job.state == .downloading { job.state = .paused }
            jobs.append(job)
        }
        return jobs
    }
    public func save(_ jobs: [DownloadJob]) throws {
        let payloads = try jobs.map { ($0.id.uuidString, String(decoding: try JSONEncoder().encode($0), as: UTF8.self)) }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM jobs")
            for (id, payload) in payloads {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT INTO jobs VALUES (?,?)", -1, &statement, nil) == SQLITE_OK else { throw failure() }
                defer { sqlite3_finalize(statement) }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                guard sqlite3_bind_text(statement, 1, id, -1, transient) == SQLITE_OK,
                      sqlite3_bind_text(statement, 2, payload, -1, transient) == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
