import Foundation
import Observation
import AbsoluteCore

@MainActor @Observable
final class DesktopStore {
    var session = DesktopSession() { didSet { scheduleSave() } }
    var browsers: [UUID: FileBrowserStore] = [:] { didSet { scheduleSave() } }
    var applications: [InstalledApplication] = []
    var launcherVisible = false
    var launcherQuery = ""
    var launcherSelection = 0
    var launchError: String?
    var catalogLoading = true
    var restoringSession = true
    var stateError: String?
    var wallpaper: Wallpaper {
        didSet { scheduleSave() }
    }
    let host = MacHost()
    let projectURL: URL
    @ObservationIgnored let stateRepository: DesktopStateRepository
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0

    init(stateRepository: DesktopStateRepository? = nil) {
        wallpaper = Wallpaper(rawValue: UserDefaults.standard.string(forKey: "absolute.wallpaper") ?? "ocean") ?? .ocean
        let candidate = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        projectURL = FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path)
            ? candidate : FileManager.default.homeDirectoryForCurrentUser
        let arguments = ProcessInfo.processInfo.arguments
        if let stateRepository { self.stateRepository = stateRepository }
        else if let flag = arguments.firstIndex(of: "--state-file"), arguments.indices.contains(flag + 1) {
            self.stateRepository = DesktopStateRepository(url: URL(fileURLWithPath: arguments[flag + 1]))
        }
        else if let flag = arguments.firstIndex(of: "--self-check"), arguments.indices.contains(flag + 1) {
            self.stateRepository = DesktopStateRepository(url: URL(fileURLWithPath: arguments[flag + 1])
                .appendingPathComponent("desktop-session.json"))
        } else { self.stateRepository = DesktopStateRepository() }
        Task { await restoreSavedSession() }
        Task {
            applications = await Task.detached(priority: .utility) { MacHost.applications() }.value
            catalogLoading = false
        }
    }

    var launcherResults: [InstalledApplication] { LauncherSearch.rank(applications, query: launcherQuery) }
    var focusedBrowser: FileBrowserStore? { session.focusedWindow.flatMap { browsers[$0.id] } }

    func openFiles(at url: URL? = nil) {
        let id = session.open(.files)
        let browser = FileBrowserStore(directory: url ?? projectURL)
        browser.stateDidChange = { [weak self] in self?.scheduleSave() }
        browsers[id] = browser
    }
    func focus(_ id: UUID) { session.focus(id) }
    func close(_ id: UUID) { session.close(id); browsers.removeValue(forKey: id) }
    func showFiles() {
        if let window = session.windows.last(where: { $0.kind == .files }) { session.focus(window.id) }
        else { openFiles() }
    }
    func toggleLauncher() {
        launcherVisible.toggle()
        launcherQuery = ""
        launcherSelection = 0
        launchError = nil
    }
    func launch(_ application: InstalledApplication) {
        guard host.open(application.url) else { launchError = "Could not open \(application.name)."; return }
        launcherVisible = false
    }
    func openEntry(_ entry: FileEntry, browser: FileBrowserStore) {
        if entry.isDirectory && entry.kind != .application { browser.navigate(to: entry.url) }
        else if !host.open(entry.url) { browser.error = "Could not open \(entry.name)." }
    }
    func openAbout() {
        if let existing = session.windows.first(where: { $0.kind == .about }) { session.focus(existing.id) }
        else { session.open(.about) }
    }

    func revealFile(_ url: URL) {
        if focusedBrowser == nil { showFiles() }
        focusedBrowser?.reveal(url)
    }

    func saveSessionNow() async {
        saveTask?.cancel()
        await writeSnapshot()
    }

    func snapshotForTermination() -> DesktopSnapshot? {
        saveTask?.cancel()
        guard !restoringSession else { return nil }
        return captureSnapshot()
    }

    private func writeSnapshot() async {
        guard !restoringSession else { return }
        let snapshot = captureSnapshot()
        do {
            _ = try await stateRepository.save(snapshot)
            stateError = nil
        } catch { stateError = error.localizedDescription }
    }

    private func captureSnapshot() -> DesktopSnapshot {
        DesktopSnapshot(session: session,
            browsers: session.windows.compactMap { browsers[$0.id]?.snapshot(windowID: $0.id) },
            wallpaper: wallpaper, revision: revision)
    }

    private func scheduleSave() {
        guard !restoringSession else { return }
        revision += 1
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self else { return }
            await self.writeSnapshot()
        }
    }

    private func restoreSavedSession() async {
        do {
            if let snapshot = try await stateRepository.load() {
                revision = snapshot.revision
                wallpaper = snapshot.wallpaper
                session = snapshot.session
                for saved in snapshot.browsers {
                    let browser = FileBrowserStore(directory: saved.directory)
                    browser.showHidden = saved.showHidden
                    browser.sort = saved.sort
                    browser.gridView = saved.gridView
                    browser.reload()
                    browser.stateDidChange = { [weak self] in self?.scheduleSave() }
                    browsers[saved.windowID] = browser
                }
            } else { openFiles(at: projectURL) }
        } catch {
            stateError = error.localizedDescription
            openFiles(at: projectURL)
        }
        restoringSession = false
    }
}
