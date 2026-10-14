import Foundation

public struct InstalledApplication: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL
    public let bundleIdentifier: String?
    public var id: String { url.path }

    public init(name: String, url: URL, bundleIdentifier: String? = nil) {
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum LauncherSearch {
    /// Exact matches precede prefixes, word prefixes, substrings, and subsequences.
    /// Ranking belongs to the portable core; launching belongs to the host.
    public static func rank(_ apps: [InstalledApplication], query: String, limit: Int = 12) -> [InstalledApplication] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return apps.compactMap { app -> (InstalledApplication, Int)? in
            let name = normalized(app.name)
            if needle.isEmpty { return (app, 0) }
            if name == needle { return (app, 1000) }
            if name.hasPrefix(needle) { return (app, 900 - max(0, name.count - needle.count)) }
            if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(needle) }) { return (app, 800) }
            if name.contains(needle) { return (app, 700) }
            var remaining = needle.makeIterator()
            var wanted = remaining.next()
            for character in name where wanted != nil {
                if character == wanted { wanted = remaining.next() }
            }
            return wanted == nil ? (app, 400 - name.count) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let order = $0.0.name.localizedStandardCompare($1.0.name)
            return order == .orderedSame ? $0.0.id < $1.0.id : order == .orderedAscending
        }.prefix(max(0, limit)).map(\.0)
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
