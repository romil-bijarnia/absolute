import SwiftUI
import AbsoluteCore

struct LauncherView: View {
    @Bindable var desktop: DesktopStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass").font(.system(size: 23)).foregroundStyle(.secondary)
                TextField("Search applications", text: $desktop.launcherQuery)
                    .font(.system(size: 25, weight: .light)).textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { launchSelected() }
                Text("esc").font(.system(size: 11)).foregroundStyle(.tertiary)
                    .padding(5).overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15)))
            }.padding(22)
            Divider()
            HStack {
                Text(desktop.launcherQuery.isEmpty ? "Applications" : "Results")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(desktop.applications.count) installed").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 22).padding(.top, 13).padding(.bottom, 5)

            if desktop.catalogLoading {
                ProgressView("Finding applications…").frame(height: 100)
            } else if desktop.launcherResults.isEmpty {
                Text("No applications match “\(desktop.launcherQuery)”.")
                    .foregroundStyle(.secondary).padding(30)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(desktop.launcherResults.enumerated()), id: \.element.id) { index, app in
                                Button { desktop.launch(app) } label: {
                                    HStack(spacing: 13) {
                                        Image(nsImage: desktop.host.icon(for: app.url)).resizable().scaledToFit().frame(width: 34, height: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name).font(.system(size: 14, weight: .medium))
                                            Text("Application").font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if desktop.launcherSelection == index { Image(systemName: "return").foregroundStyle(.secondary) }
                                    }.padding(.horizontal, 14).padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                        .background(desktop.launcherSelection == index ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain).id(index)
                                .accessibilityLabel("Launch \(app.name)")
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 10)
                    }.frame(height: min(CGFloat(desktop.launcherResults.count) * 52 + 12, 340))
                    .onChange(of: desktop.launcherSelection) { _, selection in proxy.scrollTo(selection) }
                }
            }
            if let error = desktop.launchError { Text(error).foregroundStyle(.red).font(.caption).padding(12) }
            Divider()
            HStack {
                Text("↑ ↓ to navigate")
                Spacer()
                Text("↵ to open")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 11)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18)) }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 15)
        .onAppear { searchFocused = true }
        .onChange(of: desktop.launcherQuery) { _, _ in desktop.launcherSelection = 0; desktop.launchError = nil }
        .onKeyPress(.downArrow) {
            desktop.launcherSelection = min(desktop.launcherSelection + 1, max(0, desktop.launcherResults.count - 1)); return .handled
        }
        .onKeyPress(.upArrow) { desktop.launcherSelection = max(0, desktop.launcherSelection - 1); return .handled }
        .onExitCommand { desktop.launcherVisible = false }
    }

    private func launchSelected() {
        let results = desktop.launcherResults
        guard results.indices.contains(desktop.launcherSelection) else { return }
        desktop.launch(results[desktop.launcherSelection])
    }
}
