import Foundation

public struct FileEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case folder, application, image, document, code, archive, file
    }

    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let size: Int64?
    public let modifiedAt: Date?
    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool, isSymbolicLink: Bool = false,
                size: Int64? = nil, modifiedAt: Date? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public var kind: Kind {
        let ext = url.pathExtension.lowercased()
        if ext == "app" { return .application }
        if isDirectory { return .folder }
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "svg", "tiff"].contains(ext) { return .image }
        if ["swift", "rs", "c", "h", "cpp", "py", "js", "ts", "tsx", "json", "toml", "sh", "html", "css"].contains(ext) { return .code }
        if ["zip", "gz", "tar", "dmg", "7z", "xz"].contains(ext) { return .archive }
        if ["md", "txt", "pdf", "rtf", "docx", "pages", "csv"].contains(ext) { return .document }
        return .file
    }
}

public enum FileSort: String, Codable, CaseIterable, Sendable {
    case name, modified, size
}
