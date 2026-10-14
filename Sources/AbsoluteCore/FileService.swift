import Foundation

public protocol FileService: Sendable {
    func contents(of directory: URL, showHidden: Bool, sort: FileSort) throws -> [FileEntry]
    func information(for url: URL) throws -> FileInformation
    func reveal(_ url: URL) throws -> FileRevealLocation
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
    public var errorDescription: String? { "This file service requires a local file URL." }
}

/// Foundation-backed filesystem service shared by the macOS and Linux hosts.
public struct LocalFileService: FileService {
    private static let entryKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
    ]

    public init() {}

    public func contents(of directory: URL, showHidden: Bool = false, sort: FileSort = .name) throws -> [FileEntry] {
        let directory = try localURL(directory)
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(Self.entryKeys), options: options)
        let entries = try urls.map { try readEntry($0) }
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
        var url = try localURL(url)
        url.removeAllCachedResourceValues()
        let entry = try readEntry(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let link = entry.isSymbolicLink
            ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
        return FileInformation(entry: entry, createdAt: attributes[.creationDate] as? Date,
            posixPermissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            symbolicLinkDestination: link)
    }

    public func reveal(_ url: URL) throws -> FileRevealLocation {
        var url = try localURL(url)
        url.removeAllCachedResourceValues()
        _ = try readEntry(url)
        let parent = url.deletingLastPathComponent().standardizedFileURL
        return FileRevealLocation(directory: parent, selectedURL: parent.path == url.path ? nil : url)
    }

    private func localURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
            throw FileServiceError.nonLocalURL
        }
        return url.standardizedFileURL
    }

    private func readEntry(_ url: URL) throws -> FileEntry {
        let values = try url.resourceValues(forKeys: Self.entryKeys)
        return FileEntry(url: url, name: url.lastPathComponent,
            isDirectory: values.isDirectory ?? false, isSymbolicLink: values.isSymbolicLink ?? false,
            size: values.fileSize.map(Int64.init), modifiedAt: values.contentModificationDate)
    }
}
