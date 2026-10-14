import AppKit
import AbsoluteCore

/// The host boundary. AbsoluteCore never imports AppKit or SwiftUI.
@MainActor
final class MacHost {
    static let pinnedApplicationIdentifiers = [
        "com.apple.Safari", "com.apple.Terminal", "com.apple.Notes",
        "com.apple.TextEdit", "com.apple.Preview"
    ]

    private var icons: [String: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        if let cached = icons[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        if icons.count >= 512 { icons.removeAll(keepingCapacity: true) }
        icons[url.path] = image
        return image
    }

    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func pinnedApplicationURLs() -> [URL] {
        Self.pinnedApplicationIdentifiers.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    }

    nonisolated static func applications(including registeredApplications: [URL] = []) -> [InstalledApplication] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities")]
        var applicationURLs: [URL] = []
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            applicationURLs.append(contentsOf: urls.filter { $0.pathExtension == "app" })
        }
        // Registered locations include system apps whose visible aliases are hidden.
        var found: [String: InstalledApplication] = [:]
        for url in applicationURLs + registeredApplications {
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let app = InstalledApplication(name: name, url: url, bundleIdentifier: bundle?.bundleIdentifier)
            // Prefer a user-installed app when there are several copies of a bundle.
            let identity = app.bundleIdentifier ?? app.id
            if found[identity] == nil { found[identity] = app }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
