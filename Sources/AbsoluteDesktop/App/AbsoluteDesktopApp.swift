import SwiftUI
import AppKit
import AbsoluteCore

@main
struct AbsoluteDesktopApp: App {
    @NSApplicationDelegateAdaptor(AbsoluteAppDelegate.self) private var delegate
    @State private var desktop = DesktopStore()

    var body: some Scene {
        WindowGroup("Absolute Desktop", id: "desktop") {
            DesktopView(desktop: desktop)
                .frame(minWidth: 1060, minHeight: 740)
                .task {
                    delegate.desktop = desktop
                    await AppSelfCheck.runIfRequested(desktop: desktop)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands { AbsoluteCommands(desktop: desktop) }
        Settings { AppearanceSettings(desktop: desktop) }
    }
}

struct AbsoluteCommands: Commands {
    @Bindable var desktop: DesktopStore
    @FocusedValue(\.absoluteDesktop) private var context

    var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button("New Files Window") { desktop.openFiles() }.keyboardShortcut("n")
                    .disabled(context?.restoringSession != false)
            }
            CommandMenu("Desktop") {
                Button("Search Applications") { desktop.toggleLauncher() }.keyboardShortcut("k")
                Button("Show Desktop") { desktop.session.showDesktop() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Open Home") { desktop.openFiles(at: FileManager.default.homeDirectoryForCurrentUser) }
                Divider()
                Button("About Absolute") { desktop.openAbout() }
            }
            CommandMenu("Browse") {
                Button("Back") { context?.browser?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(context?.canGoBack != true)
                Button("Forward") { context?.browser?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(context?.canGoForward != true)
                Button("Enclosing Folder") { context?.browser?.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Refresh") { context?.browser?.reload() }.keyboardShortcut("r")
                Button("Get Info") { context?.browser?.showInfoForSelection() }
                    .keyboardShortcut("i")
                    .disabled(context?.selectedEntry == nil)
                Button("Reveal Selection") {
                    if let entry = context?.selectedEntry { desktop.revealFile(entry.url) }
                }.disabled(context?.selectedEntry == nil)
                Button("Show Hidden Files") {
                    guard let browser = context?.browser else { return }
                    browser.showHidden.toggle(); browser.reload()
                }.keyboardShortcut(".", modifiers: [.command, .shift])
            }
    }
}

struct DesktopCommandContext {
    let browser: FileBrowserStore?
    let selectedEntry: FileEntry?
    let canGoBack: Bool
    let canGoForward: Bool
    let restoringSession: Bool
}

private struct DesktopCommandFocusKey: FocusedValueKey {
    typealias Value = DesktopCommandContext
}

extension FocusedValues {
    var absoluteDesktop: DesktopCommandContext? {
        get { self[DesktopCommandFocusKey.self] }
        set { self[DesktopCommandFocusKey.self] = newValue }
    }
}

@MainActor
final class AbsoluteAppDelegate: NSObject, NSApplicationDelegate {
    weak var desktop: DesktopStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let desktop, let snapshot = desktop.snapshotForTermination() else { return .terminateNow }
        let repository = desktop.stateRepository
        Task.detached {
            do { _ = try await repository.save(snapshot) }
            catch { NSLog("Absolute quit save failed: %@", error.localizedDescription) }
            // AppKit waits in a modal run loop after terminateLater.
            // Reply in a common mode, without waiting for a MainActor task.
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
}
