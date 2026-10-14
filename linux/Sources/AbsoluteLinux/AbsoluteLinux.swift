import Foundation
import AbsoluteCore
import DesktopToolkit
import Glibc

private final class Browser {
    var history: NavigationHistory
    var hidden = false
    var sort: FileSort = .name
    var grid = true
    var filter = ""
    var entries: [FileEntry] = []
    var selected: String?
    var error: String?
    var maximizedFrame: DesktopWindow?
    let view: OpaquePointer

    init(directory: URL, view: OpaquePointer) {
        history = NavigationHistory(initial: directory)
        self.view = view
    }
    var visible: [FileEntry] {
        filter.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
    var selectedEntry: FileEntry? { visible.first { $0.url.path == selected } }
}

/// GTK and all mutable presentation state stay on its main-loop thread.
/// Detached persistence tasks receive only immutable, Sendable core snapshots.
private final class LinuxDesktop {
    var native: OpaquePointer!
    var session = DesktopSession()
    var browsers: [UUID: Browser] = [:]
    var wallpaper: Wallpaper = .ocean
    var applications: [InstalledApplication] = []
    var launcherVisible = false
    var launcherQuery = ""
    var launcherSelection = 0
    var modalTitle: String?
    var modalText: String?
    var modalEntry: FileEntry?
    var revision: UInt64 = 0
    var changedAt: TimeInterval?
    var stateError: String?
    let project: URL
    let repository: DesktopStateRepository
    let service = LocalFileService()
    let debugURL: URL?

    init(project: URL, repository: DesktopStateRepository, debugURL: URL?) {
        self.project = project; self.repository = repository; self.debugURL = debugURL
    }

    func start(snapshot: DesktopSnapshot?, restoreError: String?) {
        native = al_host_new({ context, action, window, value, a, b in
            guard let context else { return }
            let desktop = Unmanaged<LinuxDesktop>.fromOpaque(context).takeUnretainedValue()
            desktop.handle(Int(action), window: window.map(String.init(cString:)) ?? "",
                           value: value.map(String.init(cString:)) ?? "", a: a, b: b)
        }, Unmanaged.passUnretained(self).toOpaque())
        stateError = restoreError
        if let snapshot {
            session = snapshot.session; wallpaper = snapshot.wallpaper; revision = snapshot.revision
            // About is a host-specific scene; the Linux host restores shared Files windows.
            for window in session.windows where window.kind != .files { session.close(window.id) }
            for saved in snapshot.browsers {
                addBrowser(id: saved.windowID, directory: saved.directory)
                guard let browser = browsers[saved.windowID] else { continue }
                browser.hidden = saved.showHidden; browser.sort = saved.sort; browser.grid = saved.gridView
                reload(browser)
            }
        } else { openFiles(at: project) }
        if session.windows.isEmpty && snapshot == nil { openFiles(at: project) }
        wallpaper.rawValue.withCString { al_host_set_wallpaper(native, $0) }
        if let restoreError { restoreError.withCString { al_host_set_notice(native, $0) } }
        al_applications({ context, name, path, identifier in
            guard let context, let name, let path else { return }
            let desktop = Unmanaged<LinuxDesktop>.fromOpaque(context).takeUnretainedValue()
            desktop.applications.append(InstalledApplication(name: String(cString: name),
                url: URL(fileURLWithPath: String(cString: path)),
                bundleIdentifier: identifier.map(String.init(cString:))))
        }, Unmanaged.passUnretained(self).toOpaque())
        applications = Array(Set(applications)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        renderFrames()
        changedAt = nil
    }

    var focused: Browser? { session.focusedWindow.flatMap { browsers[$0.id] } }
    var launcherResults: [InstalledApplication] { LauncherSearch.rank(applications, query: launcherQuery) }

    private func addBrowser(id: UUID, directory: URL) {
        guard let view = id.uuidString.withCString({ al_files_new(native, $0) }) else { return }
        let browser = Browser(directory: directory, view: view)
        browsers[id] = browser
        let home = FileManager.default.homeDirectoryForCurrentUser
        let favorites = [("Absolute", project, "drive-harddisk-symbolic"),
                         ("Home", home, "user-home-symbolic"),
                         ("Desktop", home.appendingPathComponent("Desktop"), "user-desktop-symbolic"),
                         ("Downloads", home.appendingPathComponent("Downloads"), "folder-download-symbolic"),
                         ("Computer", URL(fileURLWithPath: "/"), "computer-symbolic")]
        for (title, url, icon) in favorites {
            title.withCString { title in url.path.withCString { path in icon.withCString { icon in
                al_files_favorite(view, title, path, icon)
            }}}
        }
        reload(browser)
    }

    private func openFiles(at url: URL) {
        let id = session.open(.files)
        addBrowser(id: id, directory: url)
        renderFrames()
    }

    private func showFiles() {
        if let window = session.windows.last(where: { $0.kind == .files }) { session.focus(window.id) }
        else { openFiles(at: project) }
        renderFrames()
    }

    private func renderFrames() {
        for window in session.windows {
            guard let view = browsers[window.id]?.view else { continue }
            al_files_frame(view, window.x, window.y, window.width, window.height, window.minimized ? 0 : 1)
            al_files_raise(view)
        }
    }

    private func reload(_ browser: Browser, selecting path: String? = nil) {
        do {
            browser.entries = try service.contents(of: browser.history.current,
                showHidden: browser.hidden, sort: browser.sort)
            browser.error = nil
            browser.selected = path
        } catch {
            browser.entries = []; browser.error = error.localizedDescription; browser.selected = nil
        }
        render(browser)
    }

    private func render(_ browser: Browser) {
        let url = browser.history.current
        let title = url.lastPathComponent.isEmpty ? "Computer" : url.lastPathComponent
        let sort: Int32 = browser.sort == .name ? 0 : browser.sort == .modified ? 1 : 2
        title.withCString { title in url.path.withCString { path in browser.filter.withCString { filter in
            al_files_location(browser.view, title, path, filter,
                browser.history.canGoBack ? 1 : 0, browser.history.canGoForward ? 1 : 0,
                browser.hidden ? 1 : 0, sort, browser.grid ? 1 : 0)
        }}}
        al_files_clear(browser.view)
        let date = DateFormatter(); date.dateFormat = "dd MMM yyyy"
        for entry in browser.visible {
            let modified = entry.modifiedAt.map(date.string(from:)) ?? "—"
            let size = entry.isDirectory ? "—" : entry.size.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "—"
            entry.url.path.withCString { path in entry.name.withCString { name in
                entry.kind.rawValue.capitalized.withCString { kind in modified.withCString { modified in
                    size.withCString { size in
                        al_files_entry(browser.view, path, name, kind, modified, size, entry.isDirectory ? 1 : 0)
                    }
                }}
            }}
        }
        (browser.selected ?? "").withCString { al_files_selected(browser.view, $0) }
        let status = browser.error ?? "\(browser.visible.count) items · Ctrl+I for information · Space to preview"
        status.withCString { al_files_status(browser.view, $0) }
    }

    private func navigate(_ browser: Browser, to url: URL) {
        browser.history.navigate(to: url)
        browser.filter = ""; reload(browser)
    }

    private func reveal(_ entry: FileEntry, browser: Browser) {
        do {
            let location = try service.reveal(entry.url)
            browser.history.navigate(to: location.directory)
            browser.filter = ""
            reload(browser, selecting: location.selectedURL?.path)
            dismiss()
        } catch { showError(error.localizedDescription) }
    }

    private func info(_ browser: Browser) {
        guard let entry = browser.selectedEntry else { return }
        do {
            let details = try service.information(for: entry.url)
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            let bytes = details.entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable"
            var fields = [
                "Kind: \(details.entry.isSymbolicLink ? "Symbolic link" : details.entry.kind.rawValue.capitalized)",
                "Size: \(bytes)",
                "Location: \(entry.url.deletingLastPathComponent().path)",
                "Created: \(details.createdAt.map(formatter.string(from:)) ?? "Unavailable")",
                "Modified: \(details.entry.modifiedAt.map(formatter.string(from:)) ?? "Unavailable")"
            ]
            if let permissions = details.posixPermissions { fields.append(String(format: "Permissions: %04o", permissions & 0o7777)) }
            if let target = details.symbolicLinkDestination { fields.append("Link target: \(target)") }
            showDialog(title: entry.name, text: fields.joined(separator: "\n\n"), entry: entry)
        } catch { showError(error.localizedDescription) }
    }

    private func preview(_ browser: Browser) {
        guard let entry = browser.selectedEntry, !entry.isDirectory else { return }
        do {
            let result = try TextPreviewReader().read(entry.url)
            switch result {
            case .text(let text, let truncated):
                showDialog(title: entry.name, text: text + (truncated ? "\n\n[Preview truncated]" : ""), entry: entry)
            case .unsupported:
                showDialog(title: entry.name, text: "A text preview is unavailable for this file.", entry: entry)
            }
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ text: String) { showDialog(title: "Could not complete that action", text: text, entry: nil) }
    private func showDialog(title: String, text: String, entry: FileEntry?) {
        launcherVisible = false; modalTitle = title; modalText = text; modalEntry = entry
        title.withCString { title in text.withCString { text in
            al_host_dialog(native, title, text, entry == nil ? 0 : 1)
        }}
    }
    private func dismiss() {
        launcherVisible = false; modalTitle = nil; modalText = nil; modalEntry = nil
        al_host_dismiss(native)
    }

    private func renderLauncher() {
        al_launcher_clear(native)
        for app in launcherResults {
            app.name.withCString { name in app.url.path.withCString { path in al_launcher_entry(native, name, path) }}
        }
        launcherSelection = min(max(0, launcherSelection), max(0, launcherResults.count - 1))
        al_launcher_selected(native, Int32(launcherSelection))
    }

    private func launch(_ app: InstalledApplication) {
        if app.url.path.withCString({ al_launch_application($0) }) != 0 { dismiss() }
        else { showError("Could not launch \(app.name).") }
    }

    func handle(_ action: Int, window: String, value: String, a: Double, b: Double) {
        if action == AL_TICK { tick(); return }
        let id = UUID(uuidString: window)
        if let id, browsers[id] != nil { session.focus(id); renderFrames() }
        switch action {
        case AL_NEW_FILES: openFiles(at: project)
        case AL_SHOW_FILES: showFiles()
        case AL_SHOW_DESKTOP: session.showDesktop(); renderFrames()
        case AL_FOCUS: break
        case AL_CLOSE:
            if let id, let browser = browsers.removeValue(forKey: id) {
                session.close(id); al_files_destroy(browser.view); renderFrames()
            }
        case AL_MINIMIZE:
            if let id { session.minimize(id); renderFrames() }
        case AL_MOVE:
            if let id { session.move(id, x: a, y: b) }
        case AL_RESIZE:
            if let id { session.resize(id, width: a, height: b) }
        case AL_MAXIMIZE:
            if let id, let browser = browsers[id], let frame = session.windows.first(where: { $0.id == id }) {
                if let saved = browser.maximizedFrame {
                    session.move(id, x: saved.x, y: saved.y); session.resize(id, width: saved.width, height: saved.height)
                    browser.maximizedFrame = nil
                } else {
                    browser.maximizedFrame = frame
                    let bounds = "desktop".withCString { al_host_rect(native, $0) }
                    session.move(id, x: 16, y: 45)
                    session.resize(id, width: max(620, bounds.width - 32), height: max(360, bounds.height - 150))
                }
                renderFrames()
            }
        case AL_NAVIGATE:
            if focused == nil { showFiles() }
            if let browser = focused, !value.isEmpty { navigate(browser, to: URL(fileURLWithPath: value)) }
        case AL_BACK:
            if let browser = focused { browser.history.goBack(); browser.filter = ""; reload(browser) }
        case AL_FORWARD:
            if let browser = focused { browser.history.goForward(); browser.filter = ""; reload(browser) }
        case AL_UP:
            if let browser = focused { navigate(browser, to: browser.history.current.deletingLastPathComponent()) }
        case AL_FILTER:
            if let browser = focused, browser.filter != value { browser.filter = value; render(browser) }
        case AL_HIDDEN:
            if let browser = focused { browser.hidden = a < 0 ? !browser.hidden : a != 0; reload(browser) }
        case AL_SORT:
            if let browser = focused { browser.sort = a == 1 ? .modified : a == 2 ? .size : .name; reload(browser) }
        case AL_VIEW:
            if let browser = focused { browser.grid.toggle(); render(browser) }
        case AL_SELECT:
            if let browser = focused { browser.selected = value; value.withCString { al_files_selected(browser.view, $0) } }
        case AL_OPEN:
            if let browser = focused, let entry = browser.entries.first(where: { $0.url.path == value }) {
                if entry.isDirectory { navigate(browser, to: entry.url) }
                else if entry.url.path.withCString({ al_open_file($0) }) == 0 { showError("No application could open \(entry.name).") }
            }
        case AL_INFO: if let browser = focused { info(browser) }
        case AL_REVEAL: if let entry = modalEntry, let browser = focused { reveal(entry, browser: browser) }
        case AL_PREVIEW: if let browser = focused { preview(browser) }
        case AL_LAUNCHER:
            dismiss(); launcherVisible = true; launcherQuery = ""; launcherSelection = 0
            al_launcher_show(native); renderLauncher()
        case AL_LAUNCHER_FILTER:
            if launcherVisible { launcherQuery = value; launcherSelection = 0; renderLauncher() }
        case AL_LAUNCHER_SELECT: launcherSelection = Int(a)
        case AL_LAUNCHER_MOVE:
            launcherSelection += Int(a)
            launcherSelection = min(max(0, launcherSelection), max(0, launcherResults.count - 1))
            al_launcher_selected(native, Int32(launcherSelection))
        case AL_LAUNCHER_ACCEPT:
            if !value.isEmpty, let app = applications.first(where: { $0.url.path == value }) { launch(app) }
            else if launcherResults.indices.contains(launcherSelection) { launch(launcherResults[launcherSelection]) }
        case AL_DISMISS: dismiss()
        case AL_WALLPAPER:
            let themes = Wallpaper.allCases
            let next = ((themes.firstIndex(of: wallpaper) ?? 0) + 1) % themes.count
            wallpaper = themes[next]
            wallpaper.rawValue.withCString { al_host_set_wallpaper(native, $0) }
        case AL_TERMINAL:
            if let terminal = applications.first(where: { $0.name.lowercased().contains("xterm") }) { launch(terminal) }
            else { showError("No terminal application is installed.") }
        case AL_QUIT: al_host_quit(native)
        default: break
        }
        revision += 1; changedAt = Date.timeIntervalSinceReferenceDate
    }

    func snapshot() -> DesktopSnapshot {
        DesktopSnapshot(session: session, browsers: session.windows.compactMap { window in
            guard let browser = browsers[window.id] else { return nil }
            return FileBrowserSnapshot(windowID: window.id, directory: browser.history.current,
                showHidden: browser.hidden, sort: browser.sort, gridView: browser.grid)
        }, wallpaper: wallpaper, revision: revision)
    }

    private func tick() {
        if let changedAt, Date.timeIntervalSinceReferenceDate - changedAt >= 0.25 {
            self.changedAt = nil
            let saved = snapshot(), repository = repository
            Task.detached {
                do { _ = try await repository.save(saved) }
                catch { FileHandle.standardError.write(Data("Session save: \(error.localizedDescription)\n".utf8)) }
            }
        }
        guard let debugURL else { return }
        do {
            let state = DebugState(desktop: self)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: debugURL, options: .atomic)
        } catch { FileHandle.standardError.write(Data("Debug state: \(error.localizedDescription)\n".utf8)) }
    }
}

private struct DebugRect: Codable {
    let x, y, width, height: Double
    init(_ rect: ALRect) { x = rect.x; y = rect.y; width = rect.width; height = rect.height }
}
private struct DebugBrowser: Codable {
    let id, directory: String
    let hidden, grid, canBack, canForward: Bool
    let sort: FileSort
    let filter: String
    let selected: String?
    let names: [String]
    let error: String?
    let widgets: [String: DebugRect]
}
private struct DebugState: Encodable {
    let renderer = "GTK4"
    let snapshot: DesktopSnapshot
    let focusedWindow: UUID?
    let browsers: [DebugBrowser]
    let widgets: [String: DebugRect]
    let launcherVisible: Bool
    let launcherQuery: String
    let launcherSelection: Int
    let launcherResults: [String]
    let launcherPaths: [String]
    let applicationCount: Int
    let modalTitle, modalText: String?
    let stateError: String?

    init(desktop: LinuxDesktop) {
        snapshot = desktop.snapshot(); focusedWindow = desktop.session.focusedWindow?.id
        browsers = desktop.session.windows.compactMap { window in
            guard let browser = desktop.browsers[window.id] else { return nil }
            var widgets: [String: DebugRect] = [:]
            let roles = ["window", "titlebar", "close", "minimize", "maximize", "back", "forward", "up",
                         "path", "search", "hidden", "sort", "view", "info", "resize", "contents", "favorite:Absolute", "favorite:Home"]
                + browser.visible.map { "entry:\($0.url.path)" }
            for role in roles {
                let rect = role.withCString { al_files_rect(browser.view, $0) }
                if rect.valid != 0 { widgets[role] = DebugRect(rect) }
            }
            return DebugBrowser(id: window.id.uuidString, directory: browser.history.current.path,
                hidden: browser.hidden, grid: browser.grid, canBack: browser.history.canGoBack,
                canForward: browser.history.canGoForward, sort: browser.sort, filter: browser.filter,
                selected: browser.selected, names: browser.visible.map(\.name), error: browser.error, widgets: widgets)
        }
        var nativeWidgets: [String: DebugRect] = [:]
        for role in ["desktop", "new-files", "show-desktop", "search-apps", "dock-files", "dock-search",
                     "dock-terminal", "dock-home", "dock-wallpaper", "dialog", "dialog-close", "dialog-reveal",
                     "launcher", "launcher-search"] + desktop.launcherResults.map({ "launcher-entry:\($0.url.path)" }) {
            let rect = role.withCString { al_host_rect(desktop.native, $0) }
            if rect.valid != 0 { nativeWidgets[role] = DebugRect(rect) }
        }
        widgets = nativeWidgets
        launcherVisible = desktop.launcherVisible; launcherQuery = desktop.launcherQuery
        launcherSelection = desktop.launcherSelection; launcherResults = desktop.launcherResults.map(\.name)
        launcherPaths = desktop.launcherResults.map(\.url.path)
        applicationCount = desktop.applications.count
        modalTitle = desktop.modalTitle; modalText = desktop.modalText; stateError = desktop.stateError
    }
}

@main
struct AbsoluteLinux {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") {
            print("Absolute Linux desktop\nUsage: AbsoluteLinux [--project PATH] [--state-file PATH] [--debug-state PATH]")
            return
        }
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let project = URL(fileURLWithPath: value("--project") ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        let repository = DesktopStateRepository(url: value("--state-file").map { URL(fileURLWithPath: $0) }
            ?? DesktopStateRepository.defaultURL())
        let debugURL = value("--debug-state").map { URL(fileURLWithPath: $0) }
        var restored: DesktopSnapshot?
        var restoreError: String?
        do { restored = try await repository.load() }
        catch { restoreError = error.localizedDescription }
        let desktop = LinuxDesktop(project: project, repository: repository, debugURL: debugURL)
        desktop.start(snapshot: restored, restoreError: restoreError)
        al_host_run(desktop.native)
        do { _ = try await repository.save(desktop.snapshot()) }
        catch { FileHandle.standardError.write(Data("Quit save: \(error.localizedDescription)\n".utf8)) }
        al_host_free(desktop.native)
    }
}
