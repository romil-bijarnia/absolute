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
