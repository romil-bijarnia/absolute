import XCTest
@testable import AbsoluteCore

final class AbsoluteCoreTests: XCTestCase {
    func testNavigationAfterGoingBackStartsANewBranch() {
        var history = NavigationHistory(initial: URL(fileURLWithPath: "/start"))
        history.navigate(to: URL(fileURLWithPath: "/first"))
        history.navigate(to: URL(fileURLWithPath: "/second"))
        history.goBack()
        XCTAssertTrue(history.canGoForward)
        history.navigate(to: URL(fileURLWithPath: "/different"))
        XCTAssertFalse(history.canGoForward)
        history.goBack()
        XCTAssertEqual(history.current.path, "/first")
        history.goForward()
        XCTAssertEqual(history.current.path, "/different")
    }

    func testNavigationPreservesTraversalThroughSymbolicParent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target/nested"),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path,
            withDestinationPath: "target/nested")
        try Data("actual".utf8).write(to: root.appendingPathComponent("target/child.txt"))
        try Data("different file".utf8).write(to: root.appendingPathComponent("child.txt"))
        let request = root.appendingPathComponent("alias/..")
        let service = LocalFileService()
        var history = NavigationHistory(initial: request)
        XCTAssertEqual(history.current.path, request.path)
        XCTAssertEqual(try service.information(for: history.current.appendingPathComponent("child.txt")).entry.size, 6)

        history.navigate(to: root)
        XCTAssertEqual(try service.information(for: history.current.appendingPathComponent("child.txt")).entry.size, 14)
        history.goBack()
        XCTAssertEqual(history.current.path, request.path)
        XCTAssertEqual(try service.information(for: history.current.appendingPathComponent("child.txt")).entry.size, 6)
        history.goForward()
        history.navigate(to: request)
        XCTAssertEqual(history.current.path, request.path)
        XCTAssertEqual(try service.information(for: history.current.appendingPathComponent("child.txt")).entry.size, 6)
    }

    func testLauncherPrioritizesExactAndPrefixOverFuzzyMatches() {
        let apps = ["Terminal", "Thermal Monitor", "Terminal Helper", "Notes"].map {
            InstalledApplication(name: $0, url: URL(fileURLWithPath: "/apps/\($0).app"))
        }
        XCTAssertEqual(LauncherSearch.rank(apps, query: "terminal").map(\.name), ["Terminal", "Terminal Helper"])
        XCTAssertEqual(LauncherSearch.rank(apps, query: "trm").first?.name, "Terminal")
        XCTAssertTrue(LauncherSearch.rank(apps, query: "no such application").isEmpty)
        XCTAssertEqual(LauncherSearch.rank(apps, query: "", limit: 2).count, 2)
    }

    func testDirectoryReadHonorsHiddenFilesAndSortsFoldersFirst() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("z-folder"), withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: directory.appendingPathComponent("a-file.txt"))
        try Data().write(to: directory.appendingPathComponent(".hidden"))
        let visible = try LocalFileService().contents(of: directory)
        XCTAssertEqual(visible.map(\.name), ["z-folder", "a-file.txt"])
        XCTAssertEqual(visible.last?.size, 5)
        XCTAssertEqual(visible.last?.kind, .document)
        XCTAssertEqual(try LocalFileService().contents(of: directory, showHidden: true).count, 3)
    }

    func testMinimizedWindowsAreRestoredAndFocusedWithoutDuplication() {
        var session = DesktopSession()
        let first = session.open(.files)
        let second = session.open(.files)
        session.minimize(second)
        XCTAssertEqual(session.focusedWindow?.id, first)
        session.focus(second)
        XCTAssertEqual(session.focusedWindow?.id, second)
        XCTAssertEqual(session.windows.count, 2)
        XCTAssertFalse(session.windows.last!.minimized)
        session.close(second)
        XCTAssertEqual(session.focusedWindow?.id, first)
        session.showDesktop()
        XCTAssertNil(session.focusedWindow)
    }

    func testPreviewRetainsCompleteUTF8WhenTheByteLimitSplitsACharacter() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("preview.txt")
        try Data("abc🙂xyz".utf8).write(to: file)
        XCTAssertEqual(try TextPreviewReader().read(file, byteLimit: 5), .text("abc", truncated: true))
        try Data([0, 1, 2, 3]).write(to: file)
        XCTAssertEqual(try TextPreviewReader().read(file), .unsupported)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("absolute-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
