import SwiftUI
import AbsoluteCore

struct FileBrowserView: View {
    @Bindable var browser: FileBrowserStore
    let desktop: DesktopStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 178)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                breadcrumbs
                Divider().opacity(0.5)
                contents.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusbar
            }
            .background(.background.opacity(0.78))
        }
        .sheet(item: $browser.presentation) { presentation in
            switch presentation {
            case .preview(let entry): QuickPreviewView(entry: entry, host: desktop.host)
            case .information(let entry):
                FileInfoView(entry: entry, fileService: browser.fileService, host: desktop.host) {
                    desktop.revealFile(entry.url)
                }
            }
        }
    }

    private var favorites: [(String, String, URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("Absolute", "externaldrive", desktop.projectURL), ("Home", "house", home),
                ("Desktop", "menubar.dock.rectangle", home.appendingPathComponent("Desktop")),
                ("Documents", "doc", home.appendingPathComponent("Documents")),
                ("Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads")),
                ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"))]
    }

    private var sidebar: some View {
        List(selection: Binding<URL?>(get: { browser.directory }, set: { if let url = $0 { browser.navigate(to: url) } })) {
            Section("Favorites") {
                ForEach(favorites, id: \.2) { favorite in
                    Label {
                        Text(favorite.0)
                    } icon: {
                        Image(systemName: favorite.1).foregroundStyle(.cyan)
                    }.tag(favorite.2)
                        .font(.system(size: 13)).padding(.vertical, 3)
                }
            }
            Section("Locations") {
                Label { Text("Computer") } icon: { Image(systemName: "laptopcomputer").foregroundStyle(.cyan) }
                    .tag(URL(fileURLWithPath: "/"))
                Label { Text("System") } icon: { Image(systemName: "gearshape").foregroundStyle(.cyan) }
                    .tag(URL(fileURLWithPath: "/System"))
            }
        }
        .listStyle(.sidebar)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.navigation.canGoBack).help("Back (⌘[)").accessibilityLabel("Back")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.navigation.canGoForward).help("Forward (⌘])").accessibilityLabel("Forward")
            Text(browser.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 8)
            Button { browser.gridView.toggle() } label: {
                Image(systemName: browser.gridView ? "list.bullet" : "square.grid.2x2")
            }.help(browser.gridView ? "List view" : "Icon view").accessibilityLabel("Change file view")
            Menu {
                Picker("Sort by", selection: $browser.sort) {
                    Text("Name").tag(FileSort.name)
                    Text("Date modified").tag(FileSort.modified)
                    Text("Size").tag(FileSort.size)
                }
                Toggle("Show hidden files", isOn: $browser.showHidden)
                Button("Refresh") { browser.reload() }
            } label: { Image(systemName: "line.3.horizontal.decrease") }
                .menuStyle(.borderlessButton).fixedSize().help("File view options")
            TextField("Search this folder", text: $browser.filter)
                .textFieldStyle(.roundedBorder).frame(width: 175).accessibilityLabel("Search this folder")
        }
        .buttonStyle(.plain).padding(.horizontal, 20).frame(height: 54)
        .onChange(of: browser.sort) { _, _ in browser.reload() }
        .onChange(of: browser.showHidden) { _, _ in browser.reload() }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                ForEach(pathComponents, id: \.path) { url in
                    if url != pathComponents.first { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                    Button(url.path == "/" ? "Computer" : url.lastPathComponent) { browser.navigate(to: url) }
                        .buttonStyle(.plain).foregroundStyle(url == browser.directory ? .primary : .secondary)
                }
            }.font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 9)
        }.scrollIndicators(.hidden)
    }

    private var pathComponents: [URL] {
        let components = browser.directory.pathComponents
        return components.indices.map { index in URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1)))) }.suffix(5)
            .map { $0 }
    }

    @ViewBuilder private var contents: some View {
        if browser.loading {
            ProgressView("Opening folder…")
        } else if let error = browser.error {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Could not open this folder").font(.headline)
                Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try again") { browser.reload() }
            }.padding(30)
        } else if browser.visibleEntries.isEmpty {
            ContentUnavailableView(browser.filter.isEmpty ? "This folder is empty" : "No matching files",
                systemImage: "folder", description: Text(browser.filter.isEmpty ? "Choose another folder from the sidebar." : "Try a different search."))
        } else if browser.gridView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 106, maximum: 155), spacing: 16)], spacing: 15) {
                    ForEach(browser.visibleEntries) { entry in
                        FileTile(entry: entry, selected: browser.selectedIDs.contains(entry.id), host: desktop.host)
                            .onTapGesture(count: 2) { open(entry) }
                            .onTapGesture { browser.selectedIDs = [entry.id] }
                            .contextMenu { entryMenu(entry) }
                    }
                }.padding(24)
            }
            .focusable()
            .onKeyPress(.return) { openSelected() }
            .onKeyPress(.space) { previewSelected() }
        } else {
            Table(browser.visibleEntries, selection: $browser.selectedIDs) {
                TableColumn("Name") { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: desktop.host.icon(for: entry.url)).resizable().frame(width: 20, height: 20)
                        Text(entry.name).lineLimit(1)
                    }
                }.width(min: 180, ideal: 290)
                TableColumn("Kind") { Text($0.kind.rawValue.capitalized).foregroundStyle(.secondary) }.width(95)
                TableColumn("Modified") { entry in
                    Text(entry.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—").foregroundStyle(.secondary)
                }.width(110)
                TableColumn("Size") { entry in
                    Text(sizeLabel(entry)).foregroundStyle(.secondary)
                }.width(80)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let entry = browser.visibleEntries.first(where: { ids.contains($0.id) }) { entryMenu(entry) }
            } primaryAction: { ids in
                if let entry = browser.visibleEntries.first(where: { ids.contains($0.id) }) { open(entry) }
            }
            .onKeyPress(.return) { openSelected() }
            .onKeyPress(.space) { previewSelected() }
        }
    }

    private var statusbar: some View {
        HStack {
            Text("\(browser.visibleEntries.count) item\(browser.visibleEntries.count == 1 ? "" : "s")")
            if !browser.selectedIDs.isEmpty { Text("·  \(browser.selectedIDs.count) selected") }
            Spacer()
            Text("Space to preview").foregroundStyle(.tertiary)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30)
    }

    @ViewBuilder private func entryMenu(_ entry: FileEntry) -> some View {
        Button("Open") { open(entry) }
        if !entry.isDirectory { Button("Quick Look") { browser.presentation = .preview(entry) } }
        Button("Get Info") { browser.presentation = .information(entry) }
        Divider()
        Button("Copy Path") { desktop.host.copyPath(entry.url) }
        Button("Reveal in Files") { desktop.revealFile(entry.url) }
    }

    private func open(_ entry: FileEntry) { desktop.openEntry(entry, browser: browser) }
    private func openSelected() -> KeyPress.Result {
        guard let entry = browser.selectedEntry else { return .ignored }
        open(entry); return .handled
    }
    private func previewSelected() -> KeyPress.Result {
        guard let entry = browser.selectedEntry, !entry.isDirectory else { return .ignored }
        browser.presentation = .preview(entry); return .handled
    }
    private func sizeLabel(_ entry: FileEntry) -> String {
        guard !entry.isDirectory, let size = entry.size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct FileTile: View {
    let entry: FileEntry
    let selected: Bool
    let host: MacHost

    var body: some View {
        VStack(spacing: 7) {
            Group {
                if entry.kind == .folder {
                    Image(systemName: "folder.fill").font(.system(size: 48)).foregroundStyle(Color.cyan.gradient)
                } else {
                    Image(nsImage: host.icon(for: entry.url)).resizable().scaledToFit().frame(width: 54, height: 54)
                }
            }.frame(height: 60)
            Text(entry.name).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(selected ? Color.accentColor.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity).frame(height: 100, alignment: .top)
        .padding(6).background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
