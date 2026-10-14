import Foundation

public enum Wallpaper: String, Codable, CaseIterable, Identifiable, Sendable {
    case ocean, dusk, forest
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct FileBrowserSnapshot: Codable, Equatable, Sendable {
    public let windowID: UUID
    public let directory: URL
    public let showHidden: Bool
    public let sort: FileSort
    public let gridView: Bool

    public init(windowID: UUID, directory: URL, showHidden: Bool = false,
                sort: FileSort = .name, gridView: Bool = true) {
        self.windowID = windowID
        self.directory = directory.standardizedFileURL
        self.showHidden = showHidden
        self.sort = sort
        self.gridView = gridView
    }
}

public struct DesktopSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    public let schemaVersion: Int
    public let revision: UInt64
    public let session: DesktopSession
    public let browsers: [FileBrowserSnapshot]
    public let wallpaper: Wallpaper

    public init(session: DesktopSession, browsers: [FileBrowserSnapshot], wallpaper: Wallpaper,
                revision: UInt64 = 0, schemaVersion: Int = DesktopSnapshot.currentSchema) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.session = session
        self.browsers = browsers
        self.wallpaper = wallpaper
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchema else { throw DesktopStateError.unsupportedSchema(schemaVersion) }
        let windowIDs = session.windows.map(\.id)
        guard Set(windowIDs).count == windowIDs.count else { throw DesktopStateError.invalidSnapshot }
        let browserIDs = browsers.map(\.windowID)
        guard Set(browserIDs).count == browserIDs.count,
              Set(browserIDs) == Set(session.windows.filter { $0.kind == .files }.map(\.id)) else {
            throw DesktopStateError.invalidSnapshot
        }
        for window in session.windows {
            guard [window.x, window.y, window.width, window.height].allSatisfy(\.isFinite),
                  window.width > 0, window.height > 0 else { throw DesktopStateError.invalidSnapshot }
        }
        guard browsers.allSatisfy({ $0.directory.isFileURL && ($0.directory.host == nil || $0.directory.host == "" || $0.directory.host == "localhost") }) else {
            throw DesktopStateError.invalidSnapshot
        }
    }
}

public enum DesktopStateError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidSnapshot
    case oversizedSnapshot
    case restoreFailed
    case invalidLocation

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "This saved desktop uses an unsupported format (\(version))."
        case .invalidSnapshot: return "The saved desktop contains invalid window or folder state."
        case .oversizedSnapshot: return "The saved desktop exceeds the 1 MB state-file limit."
        case .restoreFailed: return "The saved desktop could not be restored. The original file is being preserved."
        case .invalidLocation: return "Desktop state must be stored at a local file URL."
        }
    }
}
