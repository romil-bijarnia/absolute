import Foundation
import Observation
import AbsoluteCore

@MainActor @Observable
final class FileBrowserStore {
    var navigation: NavigationHistory { didSet { stateDidChange?() } }
    var entries: [FileEntry] = []
    var selectedIDs: Set<String> = []
    var filter = ""
    var showHidden = false { didSet { stateDidChange?() } }
    var sort: FileSort = .name { didSet { stateDidChange?() } }
    var gridView = true { didSet { stateDidChange?() } }
    var loading = false
    var error: String?
    var presentation: FilePresentation?
    @ObservationIgnored let fileService: any FileService
    @ObservationIgnored var stateDidChange: (@MainActor () -> Void)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    init(directory: URL, fileService: any FileService = LocalFileService()) {
        self.fileService = fileService
        navigation = NavigationHistory(initial: directory)
        reload()
    }

    var directory: URL { navigation.current }
    var title: String { directory.lastPathComponent.isEmpty ? "Computer" : directory.lastPathComponent }
    var visibleEntries: [FileEntry] {
        guard !filter.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
    var selectedEntry: FileEntry? { visibleEntries.first { selectedIDs.contains($0.id) } }

    func navigate(to url: URL) {
        revealTask?.cancel()
        navigation.navigate(to: url)
        filter = ""
        reload()
    }
    func goBack() { revealTask?.cancel(); navigation.goBack(); filter = ""; reload() }
    func goForward() { revealTask?.cancel(); navigation.goForward(); filter = ""; reload() }
    func goUp() { navigate(to: directory.deletingLastPathComponent()) }

    func snapshot(windowID: UUID) -> FileBrowserSnapshot {
        FileBrowserSnapshot(windowID: windowID, directory: directory,
            showHidden: showHidden, sort: sort, gridView: gridView)
    }

    func reveal(_ url: URL) {
        revealTask?.cancel()
        let service = fileService
        revealTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try service.reveal(url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let location):
                navigation.navigate(to: location.directory)
                filter = ""
                reload(selecting: location.selectedURL)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    func showInfoForSelection() {
        if let entry = selectedEntry { presentation = .information(entry) }
    }

    func reload(selecting selection: URL? = nil) {
        loadTask?.cancel()
        let url = directory
        let hidden = showHidden
        let order = sort
        let service = fileService
        loading = true
        error = nil
        selectedIDs.removeAll()
        entries = []
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try service.contents(of: url, showHidden: hidden, sort: order) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let items):
                entries = items
                if let selection, let selected = items.first(where: { $0.url.path == selection.path }) {
                    selectedIDs = [selected.id]
                }
            case .failure(let failure): error = failure.localizedDescription
            }
            loading = false
        }
    }
}

enum FilePresentation: Identifiable {
    case preview(FileEntry), information(FileEntry)
    var id: String {
        switch self {
        case .preview(let entry): return "preview:\(entry.id)"
        case .information(let entry): return "information:\(entry.id)"
        }
    }
}
