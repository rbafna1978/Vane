import Foundation

/// The last snapshot, on disk.
///
/// This is what makes "opens instantly, never a launch spinner" true rather than aspirational:
/// the screen renders from here before any request is made, and the network result replaces it
/// when it arrives.
///
/// A single JSON file, not a database. The archive gets GRDB in phase 5 because it has real
/// queries; one blob keyed by cell has none, and a database for it would be furniture.
public struct SnapshotStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vane", isDirectory: true)
    }

    private func file(for cellId: String) -> URL {
        // Cell ids contain a comma and may contain a minus; both are legal in a filename, but
        // the comma is replaced anyway so the path stays obvious in a bug report.
        directory.appendingPathComponent("snapshot-\(cellId.replacingOccurrences(of: ",", with: "_")).json")
    }

    public func load(cellId: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(for: cellId)) else { return nil }
        return try? VaneClient.decoder.decode(Snapshot.self, from: data)
    }

    /// The most recent snapshot for any location — what the app shows on a cold launch, before
    /// it knows where the phone is.
    public func loadMostRecent() -> Snapshot? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        // Sort by modification date first, then decode. Decoding every saved location to find
        // the newest puts N full JSON parses on the synchronous launch path — the one path in
        // the app that must be fast, and the reason there is no launch spinner to hide behind.
        // Falls through to the next-newest if the newest file is corrupt.
        let candidates = files
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
            .compactMap { url -> (Date, URL)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else { return nil }
                return (modified, url)
            }
            .sorted { $0.0 > $1.0 }

        for (_, url) in candidates {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? VaneClient.decoder.decode(Snapshot.self, from: data) {
                return snapshot
            }
        }
        return nil
    }

    public func save(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        guard let data = try? VaneClient.encoder.encode(snapshot) else { return }
        // `.atomic` so a crash mid-write cannot leave a truncated file that fails to decode on
        // the next launch — which would turn a crash into a permanent blank screen.
        try? data.write(to: file(for: snapshot.cellId), options: .atomic)
    }
}
