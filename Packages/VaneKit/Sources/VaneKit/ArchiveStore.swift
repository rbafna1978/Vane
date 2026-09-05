import Foundation
import GRDB

/// The personal record. One row per day, from install onward.
///
/// This is the thing the brief calls "the archive" — the roll of paper the trace never leaves.
/// It is GRDB rather than SwiftData (ADR-0002) for one reason: the defining interaction is
/// compression, which is a `GROUP BY` running under a finger. SwiftData would force that
/// reduction into Swift on the main actor at 120fps.
public struct ArchiveEntry: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "archiveEntry"

    /// `yyyy-MM-dd` in the location's own zone. A string key rather than a Date so a row cannot
    /// drift across a zone boundary and become a second row for the same day.
    public var day: String
    public var cellId: String
    public var tmaxC: Double
    public var tminC: Double
    public var precipMm: Double
    public var normalTmaxC: Double?
    public var normalTminC: Double?
    public var code: Int
    public var headline: String?

    public init(
        day: String, cellId: String, tmaxC: Double, tminC: Double, precipMm: Double,
        normalTmaxC: Double? = nil, normalTminC: Double? = nil, code: Int,
        headline: String? = nil
    ) {
        self.day = day
        self.cellId = cellId
        self.tmaxC = tmaxC
        self.tminC = tminC
        self.precipMm = precipMm
        self.normalTmaxC = normalTmaxC
        self.normalTminC = normalTminC
        self.code = code
        self.headline = headline
    }
}

/// One point on the roll. At close range this is a day; further back it is a week or a month.
public struct ArchivePoint: Sendable, Hashable, Identifiable {
    public let day: String
    public let tmaxC: Double
    public let tminC: Double
    public let normalTmaxC: Double?
    public let precipMm: Double
    public let span: Int

    public var id: String { day }
    /// How far this point's high sat from the usual high. The reason the roll is worth keeping.
    public var anomaly: Double? { normalTmaxC.map { tmaxC - $0 } }
}

/// `Sendable` without `@unchecked`: GRDB's `DatabaseQueue` is itself `Sendable` and serialises
/// its own access, so there is no promise here the compiler cannot check.
public struct ArchiveStore: Sendable {
    public enum Scale: Sendable { case day, week, month }

    private let queue: DatabaseQueue

    /// - Parameter path: nil for an in-memory database, which is what the tests use.
    public init(path: String? = nil) throws {
        // `DatabaseQueue` is Sendable and serialises access, so there is no isolation ceremony
        // around reads that happen mid-gesture.
        queue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        try migrator.migrate(queue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("archive") { db in
            try db.create(table: ArchiveEntry.databaseTableName) { table in
                table.primaryKey("day", .text)
                table.column("cellId", .text).notNull()
                table.column("tmaxC", .double).notNull()
                table.column("tminC", .double).notNull()
                table.column("precipMm", .double).notNull().defaults(to: 0)
                table.column("normalTmaxC", .double)
                table.column("normalTminC", .double)
                table.column("code", .integer).notNull().defaults(to: 0)
                table.column("headline", .text)
            }
        }
        return migrator
    }

    /// Record what today was. Idempotent — opening the app five times writes one row, and a
    /// later open with better data (the cell warmed, a context line arrived) overwrites it.
    public func record(_ entry: ArchiveEntry) throws {
        try queue.write { db in try entry.save(db) }
    }

    public func entry(day: String) throws -> ArchiveEntry? {
        try queue.read { db in try ArchiveEntry.fetchOne(db, key: day) }
    }

    public func count() throws -> Int {
        try queue.read { db in try ArchiveEntry.fetchCount(db) }
    }

    /// The roll, most recent last.
    ///
    /// Aggregation happens in SQL. Pulling every row into Swift to reduce it is the thing
    /// ADR-0002 chose GRDB to avoid, and it would happen on the main actor while a finger is
    /// moving.
    public func points(scale: Scale, limit: Int = 400) throws -> [ArchivePoint] {
        let grouping: String = switch scale {
        case .day: "day"
        // SQLite has no date_trunc; strftime does the same job. %W is week-of-year.
        case .week: "strftime('%Y-W%W', day)"
        case .month: "strftime('%Y-%m', day)"
        }

        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    MIN(day)               AS day,
                    AVG(tmaxC)             AS tmaxC,
                    AVG(tminC)             AS tminC,
                    AVG(normalTmaxC)       AS normalTmaxC,
                    SUM(precipMm)          AS precipMm,
                    COUNT(*)               AS span
                FROM \(ArchiveEntry.databaseTableName)
                GROUP BY \(grouping)
                ORDER BY day DESC
                LIMIT ?
                """, arguments: [limit])

            return rows.reversed().map { row in
                ArchivePoint(
                    day: row["day"],
                    tmaxC: row["tmaxC"],
                    tminC: row["tminC"],
                    normalTmaxC: row["normalTmaxC"],
                    precipMm: row["precipMm"] ?? 0,
                    span: row["span"]
                )
            }
        }
    }

    /// Which scale the roll should be drawn at for a given number of days on screen.
    ///
    /// Compression by span, not by pinch: as more history fits in the same width, points merge
    /// so the line stays readable instead of turning into noise.
    public static func scale(forDays days: Int) -> Scale {
        switch days {
        case ..<45: .day
        case ..<400: .week
        default: .month
        }
    }
}

public extension ArchiveStore {
    /// Alongside the snapshot cache in Application Support. Not in Caches: the system may purge
    /// Caches under pressure, and this is a record that cannot be re-fetched from anywhere.
    static func defaultPath() -> String {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vane", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("archive.sqlite").path
    }
}
