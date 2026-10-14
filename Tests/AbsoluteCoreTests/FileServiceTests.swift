import XCTest
@testable import AbsoluteCore

final class FileServiceTests: XCTestCase {
    func testInformationRefreshesPreviouslyListedFileMetadata() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("example.txt")
        try Data("old".utf8).write(to: file)
        let service = LocalFileService()
        let listed = try XCTUnwrap(service.contents(of: folder).first)
        try Data("a longer replacement".utf8).write(to: file)
        let information = try service.information(for: listed.url)
        XCTAssertEqual(information.entry.size, 20)
        XCTAssertEqual(information.entry.kind, .document)
        XCTAssertNotNil(information.entry.modifiedAt)
    }

    func testRevealPreservesSymlinkIdentityAndRejectsMissingFiles() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("original.txt")
        try Data("value".utf8).write(to: file)
        let link = folder.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "original.txt")
        let service = LocalFileService()
        let location = try service.reveal(link)
        XCTAssertEqual(location.directory.path, folder.path)
        XCTAssertEqual(location.selectedURL?.path, link.path)
        let information = try service.information(for: link)
        XCTAssertTrue(information.entry.isSymbolicLink)
        XCTAssertEqual(information.symbolicLinkDestination, "original.txt")
        XCTAssertThrowsError(try service.reveal(folder.appendingPathComponent("missing")))
    }

    func testFileServiceRejectsNonLocalURLs() {
        let service = LocalFileService()
        XCTAssertThrowsError(try service.information(for: URL(string: "https://example.com/file")!))
        XCTAssertThrowsError(try service.resolve(URL(string: "https://example.com/file")!))
        XCTAssertThrowsError(try service.resolve(URL(string: "file://remote.example/file")!))
    }

    func testDanglingLinkCanBeListedInspectedAndRevealed() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let link = folder.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing.txt")
        let service = LocalFileService()

        let listed = try XCTUnwrap(service.contents(of: folder).first)
        XCTAssertEqual(listed.url.path, link.path)
        XCTAssertTrue(listed.isSymbolicLink)
        XCTAssertFalse(listed.isDirectory)
        XCTAssertEqual(listed.size, 11)
        XCTAssertEqual(try service.information(for: link).symbolicLinkDestination, "missing.txt")
        XCTAssertEqual(try service.reveal(link).selectedURL?.path, link.path)

        let unexpanded = try service.resolve(link, policy: .noFollow)
        XCTAssertEqual(unexpanded.status, .notFollowed)
        XCTAssertNil(unexpanded.resolvedURL)
        XCTAssertNil(unexpanded.posixErrorCode)
        XCTAssertEqual(unexpanded.symbolicLinkDestination, "missing.txt")

        let expanded = try service.resolve(link, policy: .follow)
        XCTAssertEqual(expanded.status, .notFound)
        XCTAssertNil(expanded.resolvedURL)
        XCTAssertNotNil(expanded.posixErrorCode)
        XCTAssertEqual(expanded.entryURL.path, link.path)
        XCTAssertEqual(expanded.symbolicLinkDestination, "missing.txt")
    }

    func testDirectoryLinkMetadataKeepsTheLinkIdentity() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("target-directory")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = folder.appendingPathComponent("directory-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target-directory")
        let service = LocalFileService()

        let information = try service.information(for: link)
        XCTAssertTrue(information.entry.isSymbolicLink)
        XCTAssertFalse(information.entry.isDirectory)
        XCTAssertEqual(information.entry.size, 16)
        XCTAssertEqual(information.symbolicLinkDestination, "target-directory")
        XCTAssertEqual(information.entry.url.path, link.path)
        let resolved = try service.resolve(link)
        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertEqual(resolved.resolvedURL?.standardizedFileURL.path, target.standardizedFileURL.path)
        XCTAssertEqual(resolved.entryURL.path, link.path)
        XCTAssertNil(resolved.posixErrorCode)
    }

    func testResolutionTraversesLinksBeforeParentComponents() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("target/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let actual = folder.appendingPathComponent("target/child.txt")
        try Data("actual".utf8).write(to: actual)
        try Data("different file".utf8).write(to: folder.appendingPathComponent("child.txt"))
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("alias").path,
            withDestinationPath: "target/nested")
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("chain").path,
            withDestinationPath: "alias")
        let request = folder.appendingPathComponent("chain/../child.txt")
        let service = LocalFileService()

        let information = try service.information(for: request)
        XCTAssertEqual(information.entry.size, 6)
        XCTAssertEqual(information.entry.url.path, request.path)
        let resolution = try service.resolve(request)
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertEqual(resolution.resolvedURL?.standardizedFileURL.path, actual.standardizedFileURL.path)
        XCTAssertEqual(resolution.entryURL.path, request.path)
        XCTAssertNil(resolution.symbolicLinkDestination)
        let revealed = try service.reveal(request)
        XCTAssertEqual(revealed.selectedURL?.path, request.path)
        XCTAssertEqual(revealed.directory.path, folder.appendingPathComponent("chain/..").path)
    }

    func testResolutionDistinguishesLoopAndNonDirectoryFailures() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("loop-a")
        try FileManager.default.createSymbolicLink(atPath: first.path, withDestinationPath: "loop-b")
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("loop-b").path,
            withDestinationPath: "loop-a")
        try Data("file".utf8).write(to: folder.appendingPathComponent("regular"))
        let invalid = folder.appendingPathComponent("non-directory-link")
        try FileManager.default.createSymbolicLink(atPath: invalid.path, withDestinationPath: "regular/child")
        let service = LocalFileService()

        let loop = try service.resolve(first)
        XCTAssertEqual(loop.status, .symbolicLinkLoop)
        XCTAssertNil(loop.resolvedURL)
        XCTAssertEqual(loop.symbolicLinkDestination, "loop-b")
        XCTAssertNotNil(loop.posixErrorCode)
        XCTAssertEqual(try service.resolve(first, policy: .noFollow).status, .notFollowed)
        XCTAssertTrue(try service.information(for: first).entry.isSymbolicLink)

        let nonDirectory = try service.resolve(invalid)
        XCTAssertEqual(nonDirectory.status, .notDirectory)
        XCTAssertNil(nonDirectory.resolvedURL)
        XCTAssertEqual(nonDirectory.symbolicLinkDestination, "regular/child")
        XCTAssertNotEqual(nonDirectory.posixErrorCode, loop.posixErrorCode)
    }

    func testResolutionThroughProtocolHandlesRegularAndMissingEntries() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("regular")
        try Data("file".utf8).write(to: file)
        let service: any FileService = LocalFileService()
        let resolved = try service.resolve(file)
        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertEqual(resolved.resolvedURL?.standardizedFileURL.path, file.standardizedFileURL.path)
        XCTAssertNil(resolved.symbolicLinkDestination)

        let missing = folder.appendingPathComponent("absent")
        for policy in [FileResolutionPolicy.noFollow, .follow] {
            let result = try service.resolve(missing, policy: policy)
            XCTAssertEqual(result.status, .notFound)
            XCTAssertNil(result.resolvedURL)
            XCTAssertNil(result.symbolicLinkDestination)
            XCTAssertNotNil(result.posixErrorCode)
        }
    }

    func testDirectoryRequirementRejectsAnOrdinaryFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("regular.txt", isDirectory: false)
        try Data("actual".utf8).write(to: file)
        let service = LocalFileService()
        XCTAssertFalse(file.hasDirectoryPath)
        XCTAssertEqual(try service.information(for: file).entry.size, 6)
        let directoryRequest = URL(fileURLWithPath: file.path + "/")
        XCTAssertTrue(directoryRequest.hasDirectoryPath)
        for policy in [FileResolutionPolicy.noFollow, .follow] {
            let result = try service.resolve(directoryRequest, policy: policy)
            XCTAssertEqual(result.status, .notDirectory)
            XCTAssertNil(result.resolvedURL)
            XCTAssertNotNil(result.posixErrorCode)
        }
        XCTAssertThrowsError(try service.information(for: directoryRequest))
        XCTAssertThrowsError(try service.reveal(directoryRequest))
    }

    func testDirectoryRequirementTraversesDirectoryLink() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = folder.appendingPathComponent("directory-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target")
        let service = LocalFileService()
        XCTAssertTrue(try service.information(for: link).entry.isSymbolicLink)
        let directoryRequest = URL(fileURLWithPath: link.path + "/")
        XCTAssertTrue(directoryRequest.hasDirectoryPath)
        for policy in [FileResolutionPolicy.noFollow, .follow] {
            let result = try service.resolve(directoryRequest, policy: policy)
            XCTAssertEqual(result.status, policy == .follow ? .resolved : .notFollowed)
            XCTAssertEqual(result.entryURL.absoluteString, directoryRequest.absoluteString)
            XCTAssertNil(result.posixErrorCode)
            XCTAssertNil(result.symbolicLinkDestination)
            if policy == .follow {
                XCTAssertEqual(result.resolvedURL?.standardizedFileURL.path, target.standardizedFileURL.path)
            } else {
                XCTAssertNil(result.resolvedURL)
            }
        }
        let information = try service.information(for: directoryRequest)
        XCTAssertTrue(information.entry.isDirectory)
        XCTAssertFalse(information.entry.isSymbolicLink)
        XCTAssertNil(information.symbolicLinkDestination)
        XCTAssertEqual(try service.reveal(directoryRequest).selectedURL?.absoluteString,
            directoryRequest.absoluteString)
    }

    func testDirectoryRequirementRejectsDanglingLink() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let link = folder.appendingPathComponent("dangling-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
        let service = LocalFileService()
        XCTAssertEqual(try service.resolve(link, policy: .noFollow).status, .notFollowed)
        let directoryRequest = URL(fileURLWithPath: link.path + "/")
        XCTAssertTrue(directoryRequest.hasDirectoryPath)
        for policy in [FileResolutionPolicy.noFollow, .follow] {
            let result = try service.resolve(directoryRequest, policy: policy)
            XCTAssertEqual(result.status, .notFound)
            XCTAssertNil(result.resolvedURL)
            XCTAssertNotNil(result.posixErrorCode)
        }
        XCTAssertThrowsError(try service.information(for: directoryRequest))
        XCTAssertThrowsError(try service.reveal(directoryRequest))
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("absolute-file-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
