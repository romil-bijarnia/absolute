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
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("absolute-file-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
