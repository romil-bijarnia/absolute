import Foundation

/// Serializes writes and refuses to replace state that failed to load.
public actor DesktopStateRepository {
    public nonisolated let url: URL
    private var examined = false
    private var blocked = false
    private var latestRevision: UInt64 = 0
    private static let byteLimit = 1024 * 1024

    public init(url: URL = DesktopStateRepository.defaultURL()) { self.url = url.isFileURL ? url.standardizedFileURL : url }

    public nonisolated static func defaultURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if os(macOS)
        return home.appendingPathComponent("Library/Application Support/Absolute/desktop-session.json")
        #else
        let configured = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
        let base = configured.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".local/state")
        return base.appendingPathComponent("absolute/desktop-session.json")
        #endif
    }

    public func load() throws -> DesktopSnapshot? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
            throw DesktopStateError.invalidLocation
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.byteLimit + 1) ?? Data()
            guard data.count <= Self.byteLimit else { throw DesktopStateError.oversizedSnapshot }
            let snapshot = try JSONDecoder().decode(DesktopSnapshot.self, from: data)
            try snapshot.validate()
            examined = true
            latestRevision = max(latestRevision, snapshot.revision)
            return snapshot
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            examined = true
            return nil
        } catch {
            examined = true
            blocked = true
            throw error
        }
    }

    @discardableResult
    public func save(_ snapshot: DesktopSnapshot) throws -> Bool {
        if !examined { _ = try load() }
        guard !blocked else { throw DesktopStateError.restoreFailed }
        try snapshot.validate()
        guard snapshot.revision >= latestRevision else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.byteLimit else { throw DesktopStateError.oversizedSnapshot }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        latestRevision = snapshot.revision
        return true
    }
}
