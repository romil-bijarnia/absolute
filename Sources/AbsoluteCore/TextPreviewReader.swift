import Foundation

public enum TextPreview: Equatable, Sendable {
    case text(String, truncated: Bool)
    case unsupported
}

public struct TextPreviewReader: Sendable {
    public init() {}

    public func read(_ url: URL, byteLimit: Int = 128 * 1024) throws -> TextPreview {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: max(1, byteLimit) + 1) ?? Data()
        let truncated = bytes.count > byteLimit
        let retained = bytes.prefix(max(1, byteLimit))
        guard !retained.contains(0) else { return .unsupported }
        // A byte limit may split the last UTF-8 scalar. Drop only that incomplete
        // tail; invalid bytes elsewhere still make this an unsupported preview.
        for trim in 0...(truncated ? min(3, retained.count) : 0) {
            if let text = String(data: Data(retained.dropLast(trim)), encoding: .utf8) {
                return .text(text, truncated: truncated)
            }
        }
        return .unsupported
    }
}
