import SwiftUI
import AbsoluteCore

/// The preview Dock. Tiles sit in a contiguous unmagnified row; while the
/// pointer is over the bar, every tile edge is displaced through
/// `DockMagnification`, so sizes, positions and the bar's extent follow the
/// geometry recovered from Dock.app rather than a per-tile hover scale.
struct DockView: View {
    @Bindable var desktop: DesktopStore
    @Environment(\.openSettings) private var openSettings
    @State private var fish: Double = 0
    @State private var center: Double = 0
    @State private var hovering = false

    static let tileSize: Double = 60
    static let largeSize: Double = 112
    private static let iconFraction = 52.0 / 60.0
    private static let separatorWidth: Double = 11
    private static let barPadding: Double = 12

    private struct Entry: Identifiable {
        enum Kind { case tile, separator }
        let id: String
        let kind: Kind
        let title: String
        let running: Bool
        let action: () -> Void
        let icon: AnyView
        var width: Double { kind == .tile ? DockView.tileSize : DockView.separatorWidth }
    }

    private var pinnedApps: [InstalledApplication] {
        MacHost.pinnedApplicationIdentifiers
            .compactMap { id in desktop.applications.first { $0.bundleIdentifier == id } }
    }

    private var entries: [Entry] {
        var items: [Entry] = [
            tile("files", "Files", running: desktop.session.windows.contains { $0.kind == .files }, action: { desktop.showFiles() },
                 icon: generatedIcon("folder.fill", colors: [.cyan, .blue])),
            tile("search", "Search · ⌘K", running: desktop.launcherVisible, action: { desktop.toggleLauncher() },
                 icon: generatedIcon("magnifyingglass", colors: [.purple, .indigo])),
            separator("apps"),
        ]
        for app in pinnedApps {
            items.append(tile("app-\(app.id)", app.name, running: false, action: { desktop.launch(app) },
                              icon: Image(nsImage: desktop.host.icon(for: app.url)).resizable().scaledToFit()))
        }
        items.append(tile("appearance", "Appearance", running: false, action: { openSettings() },
                          icon: generatedIcon("gearshape.fill", colors: [Color(white: 0.6), Color(white: 0.25)])))
        let minimized = desktop.session.windows.filter(\.minimized)
        if !minimized.isEmpty {
            items.append(separator("windows"))
            for window in minimized {
                items.append(tile("window-\(window.id)", desktop.browsers[window.id]?.title ?? "About Absolute", running: false,
                                  action: { desktop.focus(window.id) }, icon: generatedIcon("macwindow", colors: [.teal, .blue])))
            }
        }
        return items
    }

    private var magnification: DockMagnification {
        DockMagnification(tileSize: Self.tileSize, largeSize: Self.largeSize, enabled: true, fish: fish, center: center)
    }

    var body: some View {
        let entries = entries
        let rowWidth = entries.reduce(0) { $0 + $1.width }
        let model = magnification
        var positions: [Double] = []
        var cursor = 0.0
        for entry in entries { positions.append(cursor); cursor += entry.width }
        let laid = model.layout(tiles: zip(positions, entries).map { (position: $0, width: $1.width) })
        let leftShift = model.displacement(0)
        let rightShift = model.displacement(rowWidth) - rowWidth
        let barHeight = Self.largeSize + 18

        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(zip(entries, laid)), id: \.0.id) { entry, tile in
                switch entry.kind {
                case .tile:
                    DockTile(title: entry.title, running: entry.running, size: tile.size * Self.iconFraction, action: entry.action) {
                        entry.icon
                    }
                    .frame(width: tile.length, height: barHeight, alignment: .bottom)
                case .separator:
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 43).padding(.bottom, 12)
                        .frame(width: tile.length, height: barHeight, alignment: .bottom)
                }
            }
        }
        .padding(.horizontal, Self.barPadding).padding(.top, 10).padding(.bottom, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.24)) }
        .shadow(color: .black.opacity(0.28), radius: 15, y: 8)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                // The Dock compares the raw pointer position with the unmagnified row.
                center = min(max(point.x - Self.barPadding + leftShift, 0), rowWidth)
                if !hovering { hovering = true; ramp(to: 1) }
            case .ended:
                if hovering { hovering = false; ramp(to: 0) }
            }
        }
        .offset(x: (leftShift + rightShift) / 2)
        .frame(width: rowWidth + 2 * Self.barPadding, alignment: .center)
    }

    /// `startFishing` and `stopFishing`: a linear ramp whose length grows with the log of the size change.
    private func ramp(to target: Double) {
        let growth = magnification.centreGrowth
        let change = target == 1 ? Self.largeSize - (Self.tileSize + growth) : growth
        let milliseconds = DockMagnification.rampDuration(sizeChange: change)
        withAnimation(.linear(duration: milliseconds / 1000)) { fish = target }
    }

    private func tile(_ id: String, _ title: String, running: Bool, action: @escaping () -> Void, icon: some View) -> Entry {
        Entry(id: id, kind: .tile, title: title, running: running, action: action, icon: AnyView(icon))
    }

    private func separator(_ id: String) -> Entry {
        Entry(id: id, kind: .separator, title: "", running: false, action: {}, icon: AnyView(EmptyView()))
    }

    private func generatedIcon(_ symbol: String, colors: [Color]) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: proxy.size.width * 0.23)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Image(systemName: symbol).font(.system(size: proxy.size.width * 0.54, weight: .medium)).foregroundStyle(.white) }
                .overlay { RoundedRectangle(cornerRadius: proxy.size.width * 0.23).strokeBorder(.white.opacity(0.3)) }
                .padding(proxy.size.width * 0.04)
        }
    }
}

struct DockTile<Icon: View>: View {
    let title: String
    let running: Bool
    let size: Double
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon().frame(width: size, height: size)
                Circle().fill(running ? .white.opacity(0.9) : .clear).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
    }
}
