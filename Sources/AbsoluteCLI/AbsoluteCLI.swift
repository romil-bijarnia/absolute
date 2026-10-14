import Foundation
import AbsoluteCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

@main
struct AbsoluteCLI {
    static func main() async {
        do { try await execute(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("absolute: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func execute(_ arguments: [String]) async throws {
        let service = LocalFileService()
        switch arguments.first {
        case nil, "help", "--help":
            print("""
            Absolute core host
            Usage:
              absolute ls PATH [--hidden]
              absolute info PATH
              absolute reveal PATH
              absolute session STATE_FILE
              absolute verify PROJECT_PATH [REPORT_FILE]
            """)
        case "ls":
            guard arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--hidden") else { throw CommandError.usage }
            try output(service.contents(of: fileURL(arguments[1]), showHidden: arguments.count == 3))
        case "info":
            guard arguments.count == 2 else { throw CommandError.usage }
            try output(service.information(for: fileURL(arguments[1])))
        case "reveal":
            guard arguments.count == 2 else { throw CommandError.usage }
            try output(service.reveal(fileURL(arguments[1])))
        case "session":
            guard arguments.count == 2 else { throw CommandError.usage }
            let repository = DesktopStateRepository(url: fileURL(arguments[1]))
            try await output(repository.load())
        case "verify":
            guard (2...3).contains(arguments.count) else { throw CommandError.usage }
            let report = try await verify(project: fileURL(arguments[1]))
            let data = try encoded(report)
            if arguments.count == 3 {
                let destination = fileURL(arguments[2])
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            print(String(decoding: data, as: UTF8.self))
            if !report.passed { throw CommandError.checkFailed }
        default: throw CommandError.usage
        }
    }

    private static func fileURL(_ value: String) -> URL {
        URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    private static func output<T: Encodable>(_ value: T) throws {
        print(String(decoding: try encoded(value), as: UTF8.self))
    }

    private static func verify(project: URL) async throws -> CoreReport {
        let service = LocalFileService()
        var checks: [String: Bool] = [:]
        let children = try service.contents(of: project)
        checks["read_project_directory"] = children.contains { $0.name == "Package.swift" }
        let package = project.appendingPathComponent("Package.swift")
        let info = try service.information(for: package)
        checks["file_information"] = info.entry.kind == .code && (info.entry.size ?? 0) > 0
        let location = try service.reveal(package)
        checks["reveal_file"] = location.directory.path == project.path && location.selectedURL?.path == package.path
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("absolute-verify-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var session = DesktopSession()
        let id = session.open(.files)
        session.move(id, x: 140, y: 96)
        session.minimize(id)
        let snapshot = DesktopSnapshot(session: session,
            browsers: [FileBrowserSnapshot(windowID: id, directory: project, sort: .size, gridView: false)],
            wallpaper: .dusk, revision: 2)
        let stateFile = temporary.appendingPathComponent("desktop.json")
        let repository = DesktopStateRepository(url: stateFile)
        _ = try await repository.save(snapshot)
        let restored = try await DesktopStateRepository(url: stateFile).load()
        checks["desktop_state_round_trip"] = restored == snapshot
        var restoredSession = restored?.session ?? DesktopSession()
        restoredSession.focus(id)
        checks["restore_minimized_window"] = restoredSession.focusedWindow?.id == id
        let older = DesktopSnapshot(session: session, browsers: snapshot.browsers, wallpaper: .ocean, revision: 1)
        let acceptedOlder = try await repository.save(older)
        checks["reject_stale_save"] = !acceptedOlder
        let preview = try TextPreviewReader().read(package)
        if case .text(let text, _) = preview { checks["text_preview"] = text.contains("PackageDescription") }
        else { checks["text_preview"] = false }
        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "macos"
        #endif
        #if arch(arm64)
        let architecture = "aarch64"
        #else
        let architecture = "x86_64"
        #endif
        return CoreReport(platform: platform, architecture: architecture,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, checks: checks)
    }

    private struct CoreReport: Encodable {
        let platform: String
        let architecture: String
        let operatingSystem: String
        let checks: [String: Bool]
        var passed: Bool { !checks.isEmpty && checks.values.allSatisfy { $0 } }
        enum CodingKeys: String, CodingKey { case platform, architecture, operatingSystem, checks, passed }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(platform, forKey: .platform)
            try container.encode(architecture, forKey: .architecture)
            try container.encode(operatingSystem, forKey: .operatingSystem)
            try container.encode(checks, forKey: .checks)
            try container.encode(passed, forKey: .passed)
        }
    }
    private enum CommandError: LocalizedError {
        case usage, checkFailed
        var errorDescription: String? {
            self == .usage ? "Invalid arguments. Run 'absolute help' for usage." : "The core verification failed."
        }
    }
}
