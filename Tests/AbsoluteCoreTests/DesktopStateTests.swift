import XCTest
@testable import AbsoluteCore

final class DesktopStateTests: XCTestCase, @unchecked Sendable {
    func testDesktopRestoresWindowOrderFoldersAndPreferences() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("nested/desktop.json")
        var session = DesktopSession()
        let first = session.open(.files)
        let second = session.open(.files)
        session.move(first, x: 230, y: 112)
        session.resize(first, width: 780, height: 440)
        session.minimize(second)
        let snapshot = DesktopSnapshot(session: session, browsers: [
            FileBrowserSnapshot(windowID: first, directory: folder, showHidden: true, sort: .modified, gridView: false),
            FileBrowserSnapshot(windowID: second, directory: folder.appendingPathComponent("another"))
        ], wallpaper: .forest, revision: 3)
        _ = try await DesktopStateRepository(url: file).save(snapshot)
        let restored = try await DesktopStateRepository(url: file).load()
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored?.session.focusedWindow?.id, first)
    }

    func testOlderSaveCannotReplaceARecentSession() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = DesktopStateRepository(url: folder.appendingPathComponent("state.json"))
        let session = DesktopSession()
        let recent = DesktopSnapshot(session: session, browsers: [], wallpaper: .forest, revision: 4)
        let earlier = DesktopSnapshot(session: session, browsers: [], wallpaper: .ocean, revision: 3)
        _ = try await repository.save(recent)
        let accepted = try await repository.save(earlier)
        XCTAssertFalse(accepted)
        let restored = try await repository.load()
        XCTAssertEqual(restored, recent)
    }

    func testSnapshotAndStateLocationPreserveSymbolicParentTraversal() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("nested"),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path,
            withDestinationPath: "target/nested")
        try Data("actual".utf8).write(to: target.appendingPathComponent("child.txt"))
        try Data("different file".utf8).write(to: root.appendingPathComponent("child.txt"))
        let directory = root.appendingPathComponent("alias/..")
        let statePath = directory.appendingPathComponent("state.json")
        let decoy = root.appendingPathComponent("state.json")
        let original = Data("preserve the unrelated file".utf8)
        try original.write(to: decoy)
        var session = DesktopSession()
        let id = session.open(.files)
        let snapshot = DesktopSnapshot(session: session,
            browsers: [FileBrowserSnapshot(windowID: id, directory: directory)],
            wallpaper: .dusk, revision: 2)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.browsers.first?.directory.path, directory.path)

        let repository = DesktopStateRepository(url: statePath)
        XCTAssertEqual(repository.url.path, statePath.path)
        _ = try await repository.save(snapshot)
        XCTAssertEqual(try Data(contentsOf: decoy), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("state.json").path))
        let restored = try await DesktopStateRepository(url: statePath).load()
        XCTAssertEqual(restored, snapshot)
        let restoredDirectory = try XCTUnwrap(restored?.browsers.first?.directory)
        let history = NavigationHistory(initial: restoredDirectory)
        XCTAssertEqual(try LocalFileService().information(for: history.current.appendingPathComponent("child.txt")).entry.size, 6)
    }

    func testUnreadableSnapshotIsPreservedWhenSaveIsAttempted() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let original = Data("{ incomplete".utf8)
        try original.write(to: file)
        let repository = DesktopStateRepository(url: file)
        do { _ = try await repository.load(); XCTFail("Malformed state was accepted") } catch {}
        do {
            _ = try await repository.save(DesktopSnapshot(session: DesktopSession(), browsers: [], wallpaper: .ocean))
            XCTFail("Malformed state was replaced")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testUnknownSchemaAndMissingBrowserAreRejected() throws {
        let unsupported = DesktopSnapshot(session: DesktopSession(), browsers: [], wallpaper: .ocean, schemaVersion: 9)
        XCTAssertThrowsError(try unsupported.validate())
        var session = DesktopSession()
        session.open(.files)
        XCTAssertThrowsError(try DesktopSnapshot(session: session, browsers: [], wallpaper: .ocean).validate())
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("absolute-state-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
