import SwiftUI
import AbsoluteCore

struct DesktopView: View {
    @Bindable var desktop: DesktopStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                WallpaperView(wallpaper: desktop.wallpaper)
                    .onTapGesture { desktop.launcherVisible = false }

                desktopIcons
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 64).padding(.trailing, 28)

                ForEach(desktop.session.windows.filter { !$0.minimized }) { window in
                    DesktopWindowView(desktop: desktop, window: window, bounds: geometry.size) {
                        switch window.kind {
                        case .files:
                            if let browser = desktop.browsers[window.id] {
                                FileBrowserView(browser: browser, desktop: desktop)
                            }
                        case .about: AboutView()
                        }
                    }
                    .zIndex(Double(desktop.session.windows.firstIndex(where: { $0.id == window.id }) ?? 0) + 1)
                }

                DesktopMenuBar(desktop: desktop)
                    .frame(maxWidth: .infinity).zIndex(100)

                DockView(desktop: desktop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 15).zIndex(101)

                if desktop.launcherVisible {
                    Color.black.opacity(0.15)
                        .onTapGesture { desktop.launcherVisible = false }.zIndex(200)
                    LauncherView(desktop: desktop)
                        .frame(width: 650)
                        .position(x: geometry.size.width / 2, y: min(geometry.size.height * 0.44, 360))
                        .zIndex(201)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.16), value: desktop.launcherVisible)
        }
        .disabled(desktop.restoringSession)
        .preferredColorScheme(.dark)
        .focusedSceneValue(\.absoluteDesktop, DesktopCommandContext(
            browser: desktop.focusedBrowser,
            selectedEntry: desktop.focusedBrowser?.selectedEntry,
            canGoBack: desktop.focusedBrowser?.navigation.canGoBack ?? false,
            canGoForward: desktop.focusedBrowser?.navigation.canGoForward ?? false,
            restoringSession: desktop.restoringSession))
    }

    private var desktopIcons: some View {
        VStack(spacing: 24) {
            desktopIcon("Absolute", symbol: "externaldrive.fill", color: .gray) {
                desktop.openFiles(at: desktop.projectURL)
            }
            desktopIcon("Home", symbol: "folder.fill", color: .cyan) {
                desktop.openFiles(at: FileManager.default.homeDirectoryForCurrentUser)
            }
            desktopIcon("Research", symbol: "folder.fill", color: .cyan) {
                let research = desktop.projectURL.appendingPathComponent("research")
                desktop.openFiles(at: FileManager.default.fileExists(atPath: research.path) ? research : desktop.projectURL)
            }
        }
    }

    private func desktopIcon(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 43)).foregroundStyle(color.gradient)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
            }.frame(width: 90)
        }.buttonStyle(.plain).accessibilityLabel("Open \(title)")
    }
}

struct DesktopMenuBar: View {
    @Bindable var desktop: DesktopStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 19) {
            Menu {
                Button("About Absolute") { desktop.openAbout() }
                Button("Appearance…") { openSettings() }
                if let error = desktop.stateError {
                    Divider()
                    Text("Saved desktop unavailable")
                    Text(error)
                }
                Divider()
                Button("Quit Absolute") { NSApplication.shared.terminate(nil) }
            } label: {
                Text("Absolute").fontWeight(.semibold)
            }
            .menuStyle(.borderlessButton).fixedSize()

            Menu("File") {
                Button("New Files Window") { desktop.openFiles() }
                if let focused = desktop.session.focusedWindow {
                    Button("Close Window") { desktop.close(focused.id) }
                }
            }.menuStyle(.borderlessButton).fixedSize()
            Menu("View") {
                Button("Show Desktop") { desktop.session.showDesktop() }
                Button("Show Files") { desktop.showFiles() }
                Button("Search Applications") { desktop.toggleLauncher() }
            }.menuStyle(.borderlessButton).fixedSize()
            Menu("Go") {
                Button("Home") { desktop.openFiles(at: FileManager.default.homeDirectoryForCurrentUser) }
                Button("Applications") { desktop.openFiles(at: URL(fileURLWithPath: "/Applications")) }
                Button("Project") { desktop.openFiles(at: desktop.projectURL) }
            }.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Button { desktop.toggleLauncher() } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Search applications (⌘K)").accessibilityLabel("Search applications")
            Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).help("Appearance").accessibilityLabel("Appearance settings")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 84).padding(.trailing, 18).frame(height: 31)
        .background(.ultraThinMaterial)
    }
}
