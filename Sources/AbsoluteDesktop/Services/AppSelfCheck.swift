import AppKit
import Foundation
import AbsoluteCore

/// An opt-in integration check of our own app, invoked by the local run script.
/// It uses AppKit's responder chain and captures only this app's content view.
@MainActor
enum AppSelfCheck {
    private static var started = false

    static func runIfRequested(desktop: DesktopStore) async {
        let arguments = ProcessInfo.processInfo.arguments
        let restoring = arguments.contains("--restore-check")
        guard !started, let flag = arguments.firstIndex(of: restoring ? "--restore-check" : "--self-check"),
              arguments.indices.contains(flag + 1) else { return }
        started = true
        let output = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        if restoring {
            await checkRestoredSession(desktop: desktop, output: output)
            return
        }
        var checks: [String: Bool] = [:]
        var errors: [String] = []
        var diagnostics: [String: Any] = [:]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            checks["initial_session_ready"] = await waitUntil { !desktop.restoringSession }
            checks["application_catalog_loaded"] = await waitUntil { !desktop.catalogLoading && !desktop.applications.isEmpty }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let mainID = desktop.session.focusedWindow?.id, let browser = desktop.browsers[mainID] else {
                throw CheckFailure("The desktop did not present its initial files window.")
            }
            checks["initial_folder_loaded"] = await waitUntil { !browser.loading && !browser.entries.isEmpty }
            await settle()
            try capture(window, to: output.appendingPathComponent("01-desktop.png"))

            let initial = browser.directory
            let sources = desktop.projectURL.appendingPathComponent("Sources")
            browser.navigate(to: sources)
            checks["navigate_to_real_folder"] = await waitUntil {
                !browser.loading && browser.directory == sources && browser.entries.contains { $0.name == "AbsoluteCore" }
            }
            browser.filter = "AbsoluteCore"
            checks["folder_search"] = browser.visibleEntries.map(\.name) == ["AbsoluteCore"]
            browser.filter = ""
            browser.gridView = false
            await settle()
            try capture(window, to: output.appendingPathComponent("02-file-list.png"))
            browser.goBack()
            checks["back_navigation"] = await waitUntil { !browser.loading && browser.directory == initial }
            browser.goForward()
            checks["forward_navigation"] = await waitUntil { !browser.loading && browser.directory == sources }
            browser.navigate(to: initial)
            browser.gridView = true
            _ = await waitUntil { !browser.loading }

            desktop.session.minimize(mainID)
            checks["minimize_window"] = desktop.session.focusedWindow == nil
            desktop.showFiles()
            checks["dock_restores_window"] = desktop.session.focusedWindow?.id == mainID && desktop.session.windows.count == 1
            desktop.openFiles(at: sources)
            checks["independent_file_windows"] = desktop.browsers.count == 2 && desktop.browsers[mainID]?.directory == initial
            if let second = desktop.session.focusedWindow?.id, second != mainID { desktop.close(second) }
            checks["close_restores_focus"] = desktop.session.focusedWindow?.id == mainID

            if let event = keyEvent(window, key: "k", keyCode: 40, modifiers: .command) {
                checks["launcher_keyboard_command"] = NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            }
            checks["launcher_presented"] = await waitUntil { desktop.launcherVisible }
            desktop.launcherQuery = ""
            await settle()
            if let event = keyEvent(window, key: "\u{f701}", keyCode: 125) { NSApp.sendEvent(event) }
            checks["launcher_arrow_down"] = await waitUntil { desktop.launcherSelection == 1 }
            if let event = keyEvent(window, key: "\u{f700}", keyCode: 126) { NSApp.sendEvent(event) }
            checks["launcher_arrow_up"] = await waitUntil { desktop.launcherSelection == 0 }
            desktop.launcherQuery = "Terminal"
            await settle()
            checks["launcher_matches_installed_app"] = desktop.launcherResults.first?.bundleIdentifier == "com.apple.Terminal"
            checks["launcher_search_field_focused"] = window.firstResponder is NSTextView
            try capture(window, to: output.appendingPathComponent("03-launcher.png"))
            if let event = keyEvent(window, key: "\u{1b}", keyCode: 53) { NSApp.sendEvent(event) }
            checks["escape_dismisses_launcher"] = await waitUntil { !desktop.launcherVisible }
            desktop.launcherVisible = false
            desktop.launcherQuery = ""
            await settle()

            browser.navigate(to: sources)
            _ = await waitUntil { !browser.loading && browser.directory == sources }
            let package = desktop.projectURL.appendingPathComponent("Package.swift")
            desktop.revealFile(package)
            checks["reveal_navigates_and_selects"] = await waitUntil {
                !browser.loading && browser.directory.path == desktop.projectURL.path &&
                    browser.selectedEntry?.url.path == package.path
            }
            await settle()
            updateMenus(NSApp.mainMenu)
            diagnostics["info_menu_items"] = menuDiagnostics(NSApp.mainMenu)
            diagnostics["selected_before_info"] = browser.selectedEntry?.url.path ?? ""
            diagnostics["focused_browser_is_original"] = desktop.focusedBrowser === browser
            if arguments.contains("--background") {
                // There is no focused scene while the app is inactive.
                // Exercise the same action directly without activating it.
                let infoItem = menuItem(named: "Get Info", in: NSApp.mainMenu)
                checks["file_info_shortcut_registered"] = infoItem?.keyEquivalent == "i" &&
                    infoItem?.keyEquivalentModifierMask == .command
                browser.showInfoForSelection()
            } else if let event = keyEvent(window, key: "i", keyCode: 34, modifiers: .command) {
                checks["file_info_keyboard_command"] = NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            }
            checks["file_info_requested"] = await waitUntil {
                if case .information(let entry) = browser.presentation { return entry.url.path == package.path }
                return false
            }
            checks["file_info_presented"] = await waitUntil {
                if case .information(let entry) = browser.presentation {
                    return entry.url.path == package.path && window.attachedSheet != nil
                }
                return false
            }
            await settle()
            guard let sheet = window.attachedSheet else { throw CheckFailure("Get Info did not present a native sheet.") }
            try capture(sheet, to: output.appendingPathComponent("04-file-info.png"))
            browser.presentation = nil
            checks["file_info_dismissed"] = await waitUntil { window.attachedSheet == nil }

            browser.showHidden = true
            browser.sort = .modified
            browser.gridView = false
            browser.reload()
            desktop.session.move(mainID, x: 118, y: 78)
            desktop.session.resize(mainID, width: 980, height: 570)
            desktop.openFiles(at: sources)
            guard let secondID = desktop.session.focusedWindow?.id, secondID != mainID else {
                throw CheckFailure("Could not prepare a second window for the restart check.")
            }
            desktop.session.minimize(secondID)
            desktop.wallpaper = .forest
            _ = await waitUntil { desktop.browsers.values.allSatisfy { !$0.loading } }
            await desktop.saveSessionNow()
            let saved = try await desktop.stateRepository.load()
            checks["desktop_session_saved"] = saved?.session == desktop.session &&
                saved?.wallpaper == .forest && saved?.browsers == browserSnapshots(desktop)
            checks["state_save_has_no_error"] = desktop.stateError == nil
            if arguments.contains("--background") { checks["background_launch_keeps_focus"] = !NSApp.isActive }

            // The final change is intentionally left to the normal quit handler.
            // A fresh process must restore it together with the window and folder state.
            desktop.wallpaper = .dusk
            let expected = DesktopSnapshot(session: desktop.session,
                browsers: browserSnapshots(desktop), wallpaper: .dusk)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(expected).write(to: output.appendingPathComponent("expected-session.json"), options: .atomic)
        } catch { errors.append(error.localizedDescription) }

        let report: [String: Any] = [
            "passed": !checks.isEmpty && checks.values.allSatisfy { $0 } && errors.isEmpty,
            "checks": checks, "errors": errors,
            "diagnostics": diagnostics,
            "process_identifier": ProcessInfo.processInfo.processIdentifier,
            "native_windows": NSApp.windows.map {
                ["title": $0.title, "visible": $0.isVisible, "key": $0.isKeyWindow, "main": $0.isMainWindow,
                    "sheet": $0.isSheet, "attached_sheet": $0.attachedSheet != nil]
            },
            "application_count": desktop.applications.count,
            "screenshots": ["01-desktop.png", "02-file-list.png", "03-launcher.png", "04-file-info.png"],
            "limitations": arguments.contains("--background")
                ? ["Get Info shortcut activation requires a focused scene; background mode checks its registration and invokes the same action directly."]
                : [],
            "scope": "Native presentation, file navigation and reveal, Get Info, window state, search, keyboard routing, and saved sessions. External application launches are not exercised."
        ]
        writeReport(report, to: output.appendingPathComponent("results.json"))
        if arguments.contains("--exit-after-check") { DispatchQueue.main.async { NSApp.terminate(nil) } }
    }

    private static func checkRestoredSession(desktop: DesktopStore, output: URL) async {
        var checks: [String: Bool] = [:]
        var errors: [String] = []
        do {
            checks["restoration_finished"] = await waitUntil { !desktop.restoringSession }
            let data = try Data(contentsOf: output.appendingPathComponent("expected-session.json"))
            let expected = try JSONDecoder().decode(DesktopSnapshot.self, from: data)
            checks["window_layout_and_minimization_restored"] = desktop.session == expected.session
            checks["folder_preferences_restored"] = browserSnapshots(desktop) == expected.browsers
            checks["quit_flushed_final_wallpaper_change"] = desktop.wallpaper == expected.wallpaper
            checks["restored_folders_loaded"] = await waitUntil {
                !desktop.browsers.isEmpty && desktop.browsers.values.allSatisfy { !$0.loading && $0.error == nil }
            }
            checks["restore_has_no_error"] = desktop.stateError == nil
            if ProcessInfo.processInfo.arguments.contains("--background") {
                checks["background_restart_keeps_focus"] = !NSApp.isActive
            }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                throw CheckFailure("The restarted desktop did not present its native window.")
            }
            await settle()
            try capture(window, to: output.appendingPathComponent("05-session-restored.png"))
        } catch { errors.append(error.localizedDescription) }
        let report: [String: Any] = [
            "passed": !checks.isEmpty && checks.values.allSatisfy { $0 } && errors.isEmpty,
            "checks": checks, "errors": errors,
            "process_identifier": ProcessInfo.processInfo.processIdentifier,
            "screenshots": ["05-session-restored.png"],
            "scope": "A fresh application process restoring the prior desktop after normal termination."
        ]
        writeReport(report, to: output.appendingPathComponent("restore-results.json"))
        if ProcessInfo.processInfo.arguments.contains("--exit-after-check") {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func browserSnapshots(_ desktop: DesktopStore) -> [FileBrowserSnapshot] {
        desktop.session.windows.compactMap { desktop.browsers[$0.id]?.snapshot(windowID: $0.id) }
    }

    private static func menuDiagnostics(_ menu: NSMenu?) -> [[String: Any]] {
        guard let menu else { return [] }
        return menu.items.flatMap { item in
            var result = menuDiagnostics(item.submenu)
            if item.keyEquivalent.lowercased() == "i" || item.title == "Get Info" {
                result.append(["title": item.title, "key": item.keyEquivalent, "enabled": item.isEnabled,
                    "modifiers": item.keyEquivalentModifierMask.rawValue])
            }
            return result
        }
    }

    private static func updateMenus(_ menu: NSMenu?) {
        guard let menu else { return }
        menu.update()
        for item in menu.items { updateMenus(item.submenu) }
    }

    private static func menuItem(named title: String, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title == title { return item }
            if let nested = menuItem(named: title, in: item.submenu) { return nested }
        }
        return nil
    }

    private static func writeReport(_ report: [String: Any], to url: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { NSLog("Absolute self-check report failed: %@", error.localizedDescription) }
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(350)) }

    private static func keyEvent(_ window: NSWindow, key: String, keyCode: UInt16,
                                 modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode)
    }

    private static func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CheckFailure("Could not create a bitmap for our own window.")
        }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure("Could not encode the native window capture.")
        }
        try data.write(to: url, options: .atomic)
    }

    private struct CheckFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
