import SwiftUI
import AbsoluteCore

struct DockView: View {
    @Bindable var desktop: DesktopStore
    @Environment(\.openSettings) private var openSettings

    private var pinnedApps: [InstalledApplication] {
        MacHost.pinnedApplicationIdentifiers
            .compactMap { id in desktop.applications.first { $0.bundleIdentifier == id } }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            DockTile(title: "Files", running: desktop.session.windows.contains { $0.kind == .files }) {
                desktop.showFiles()
            } icon: { generatedIcon("folder.fill", colors: [.cyan, .blue]) }

            DockTile(title: "Search · ⌘K", running: desktop.launcherVisible) {
                desktop.toggleLauncher()
            } icon: { generatedIcon("magnifyingglass", colors: [.purple, .indigo]) }

            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 43).padding(.horizontal, 5).padding(.bottom, 12)

            ForEach(pinnedApps) { app in
                DockTile(title: app.name, running: false) { desktop.launch(app) } icon: {
                    Image(nsImage: desktop.host.icon(for: app.url)).resizable().scaledToFit()
                }
            }

            DockTile(title: "Appearance", running: false) { openSettings() } icon: {
                generatedIcon("gearshape.fill", colors: [Color(white: 0.6), Color(white: 0.25)])
            }

            if desktop.session.windows.contains(where: \.minimized) {
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 43).padding(.horizontal, 5).padding(.bottom, 12)
                ForEach(desktop.session.windows.filter(\.minimized)) { window in
                    DockTile(title: desktop.browsers[window.id]?.title ?? "About Absolute", running: false) {
                        desktop.focus(window.id)
                    } icon: { generatedIcon("macwindow", colors: [.teal, .blue]) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.24)) }
        .shadow(color: .black.opacity(0.28), radius: 15, y: 8)
    }

    private func generatedIcon(_ symbol: String, colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(.white) }
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.3)) }
            .padding(2)
    }
}

struct DockTile<Icon: View>: View {
    let title: String
    let running: Bool
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon().frame(width: 52, height: 52)
                    .scaleEffect(hovered ? 1.16 : 1, anchor: .bottom)
                Circle().fill(running ? .white.opacity(0.9) : .clear).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
        .onHover { hovered = $0 }
        .overlay(alignment: .top) {
            if hovered {
                Text(title).font(.system(size: 11)).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .offset(y: -38).allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.7), value: hovered)
    }
}
