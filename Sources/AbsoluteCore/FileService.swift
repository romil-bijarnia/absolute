import Foundation

public protocol FileService: Sendable {
    func contents(of directory: URL, showHidden: Bool, sort: FileSort) throws -> [FileEntry]
    func information(for url: URL) throws -> FileInformation
    func reveal(_ url: URL) throws -> FileRevealLocation
    func resolve(_ url: URL, policy: FileResolutionPolicy) throws -> FileResolution
}

public extension FileService {
    func resolve(_ url: URL) throws -> FileResolution {
        try resolve(url, policy: .follow)
    }

    func resolve(_ url: URL, policy: FileResolutionPolicy) throws -> FileResolution {
        throw FileServiceError.resolutionUnavailable
    }
}

public struct FileInformation: Codable, Equatable, Sendable {
    public let entry: FileEntry
    public let createdAt: Date?
    public let posixPermissions: UInt16?
    public let symbolicLinkDestination: String?
}

public struct FileRevealLocation: Codable, Equatable, Sendable {
    public let directory: URL
    public let selectedURL: URL?
}

public enum FileServiceError: LocalizedError {
    case nonLocalURL
    case resolutionUnavailable
    public var errorDescription: String? {
        switch self {
        case .nonLocalURL: "This file service requires a local file URL."
        case .resolutionUnavailable: "This file service does not support path resolution."
        }
    }
}

/// Foundation-backed filesystem service shared by the macOS and Linux hosts.
public struct LocalFileService: FileService {
    public init() {}

    public func contents(of directory: URL, showHidden: Bool = false, sort: FileSort = .name) throws -> [FileEntry] {
        let directory = try localURL(directory)
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: options)
        let entries = try urls.map {
            try readEntry(directory.appendingPathComponent($0.lastPathComponent, isDirectory: false))
        }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            switch sort {
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt { return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast) }
            case .size:
                if lhs.size != rhs.size { return (lhs.size ?? 0) > (rhs.size ?? 0) }
            case .name: break
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public func information(for url: URL) throws -> FileInformation {
        let url = try localURL(url)
        let path = FilePathResolver.fileSystemPath(for: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let entry = readEntry(url, attributes: attributes)
        let link = entry.isSymbolicLink
            ? try FileManager.default.destinationOfSymbolicLink(atPath: path) : nil
        return FileInformation(entry: entry, createdAt: attributes[.creationDate] as? Date,
            posixPermissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            symbolicLinkDestination: link)
    }

    public func reveal(_ url: URL) throws -> FileRevealLocation {
        let url = try localURL(url)
        _ = try readEntry(url)
        let parent = url.deletingLastPathComponent()
        return FileRevealLocation(directory: parent, selectedURL: parent.path == url.path ? nil : url)
    }

    public func resolve(_ url: URL, policy: FileResolutionPolicy = .follow) throws -> FileResolution {
        FilePathResolver.resolve(try localURL(url), policy: policy)
    }

    private func localURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
            throw FileServiceError.nonLocalURL
        }
        return url.absoluteURL
    }

    private func readEntry(_ url: URL) throws -> FileEntry {
        readEntry(url, attributes: try FileManager.default.attributesOfItem(
            atPath: FilePathResolver.fileSystemPath(for: url)))
    }

    private func readEntry(_ url: URL, attributes: [FileAttributeKey: Any]) -> FileEntry {
        let type = attributes[.type] as? FileAttributeType
        return FileEntry(url: url, name: url.lastPathComponent,
            isDirectory: type == .typeDirectory, isSymbolicLink: type == .typeSymbolicLink,
            size: (attributes[.size] as? NSNumber)?.int64Value,
            modifiedAt: attributes[.modificationDate] as? Date)
    }
}
