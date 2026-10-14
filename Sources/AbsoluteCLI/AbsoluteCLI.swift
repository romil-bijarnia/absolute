import Foundation
import AbsoluteCore
import AbsoluteMach
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
              absolute mach-demo [REPORT_FILE]
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
        case "mach-demo":
            guard arguments.count <= 2 else { throw CommandError.usage }
            let report = try await machDemo()
            if arguments.count == 2 {
                let destination = fileURL(arguments[1])
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoded(report).write(to: destination, options: .atomic)
            }
            try output(report)
            if !report.passed { throw CommandError.checkFailed }
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
        let expanded = (value as NSString).expandingTildeInPath
        // NSString's tilde expansion removes trailing slashes even when the
        // input contains no tilde. Retain the caller's directory requirement.
        if value.hasSuffix("/") { return URL(fileURLWithPath: expanded, isDirectory: true) }
        return URL(fileURLWithPath: expanded)
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
        checks.merge(try await verifySymbolicParentPaths(in: temporary)) { _, new in new }
        let mach = try await machDemo()
        checks["portable_mach_message_round_trip"] = mach.passed
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

    private static func machDemo() async throws -> MachDemoReport {
        let namespace = MachPortSpace()
        let destination = try await namespace.allocateReceiveRight()
        let inserted = try await namespace.insertSendRight(destination)
        let payload = Data("Absolute IPC v1.".utf8)
        let request = try MachMessage(bits: MachMessageHeader.makeBits(remote: 19),
            remotePort: destination, id: 42, payload: payload)
        let sent = try await namespace.send(request.encode())
        let received = try await namespace.receive(destination, capacity: 256)
        let reply = try MachMessage.decode(received.buffer)
        let state = await namespace.state(of: destination)
        let releasedReceive = await namespace.releaseReceiveRight(destination)
        let releasedSend = await namespace.deallocateNameReference(destination)
        let checks = [
            "send_right_created": inserted == .success,
            "send_and_receive_succeeded": sent.status == .success && received.status == .success,
            "payload_preserved": reply.payload == payload,
            "header_transformed": reply.header.bits == 0x1100 && reply.header.remotePort == 0
                && reply.header.localPort == destination && reply.header.id == 42,
            "default_trailer_returned": reply.trailingBytes == Data([0, 0, 0, 0, 8, 0, 0, 0]),
            "copy_send_reference_preserved": state.sendReferences == 1 && state.queueCount == 0,
            "rights_released": releasedReceive == .success && releasedSend == .success
        ]
        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "macos"
        #endif
        return MachDemoReport(platform: platform,
            scope: "AbsoluteMach in-process namespace; nonblocking inline message subset.",
            receivedText: String(decoding: reply.payload, as: UTF8.self),
            receivedMessageHex: reply.encode().map { String(format: "%02x", $0) }.joined(),
            checks: checks, passed: checks.values.allSatisfy { $0 })
    }

    private struct MachDemoReport: Encodable {
        let platform: String
        let scope: String
        let receivedText: String
        let receivedMessageHex: String
        let checks: [String: Bool]
        let passed: Bool
    }

    private static func verifySymbolicParentPaths(in temporary: URL) async throws -> [String: Bool] {
        let root = temporary.appendingPathComponent("path-traversal")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("nested"),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path,
            withDestinationPath: "target/nested")
        try Data("actual".utf8).write(to: target.appendingPathComponent("child.txt"))
        try Data("different file".utf8).write(to: root.appendingPathComponent("child.txt"))
        let directory = root.appendingPathComponent("alias/..")
        let requestedFile = directory.appendingPathComponent("child.txt")
        var checks: [String: Bool] = [:]

        // Run real child commands so argument parsing and serialization are part
        // of the check, including the literal link/../child path from the shell.
        let information = try captureCommand(["info", requestedFile.path], as: FileInformation.self)
        checks["cli_info_preserves_symlink_parent"] = information.entry.size == 6 &&
            information.entry.url.path == requestedFile.path
        let entries = try captureCommand(["ls", directory.path], as: [FileEntry].self)
        checks["cli_ls_preserves_symlink_parent"] = entries.contains { $0.name == "child.txt" && $0.size == 6 } &&
            entries.contains { $0.name == "nested" && $0.isDirectory }
        let revealed = try captureCommand(["reveal", requestedFile.path], as: FileRevealLocation.self)
        checks["cli_reveal_preserves_symlink_parent"] = revealed.directory.path == directory.path &&
            revealed.selectedURL?.path == requestedFile.path

        var session = DesktopSession()
        let id = session.open(.files)
        let snapshot = DesktopSnapshot(session: session,
            browsers: [FileBrowserSnapshot(windowID: id, directory: directory)],
            wallpaper: .forest, revision: 2)
        let decoy = root.appendingPathComponent("desktop.json")
        let original = Data("preserve the unrelated file".utf8)
        try original.write(to: decoy)
        let statePath = directory.appendingPathComponent("desktop.json")
        _ = try await DesktopStateRepository(url: statePath).save(snapshot)
        checks["session_write_preserves_symlink_parent"] = try Data(contentsOf: decoy) == original &&
            FileManager.default.fileExists(atPath: target.appendingPathComponent("desktop.json").path)
        let restored = try captureCommand(["session", statePath.path], as: DesktopSnapshot.self)
        checks["cli_session_preserves_symlink_parent"] = restored == snapshot &&
            restored.browsers.first?.directory.path == directory.path

        let directoryLink = root.appendingPathComponent("directory-link", isDirectory: false)
        let danglingLink = root.appendingPathComponent("dangling-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(atPath: directoryLink.path, withDestinationPath: "target")
        try FileManager.default.createSymbolicLink(atPath: danglingLink.path, withDestinationPath: "missing")
        for (name, path) in [
            ("cli_rejects_file_with_trailing_slash", requestedFile.path + "/"),
            ("cli_rejects_dangling_link_with_trailing_slash", danglingLink.path + "/")
        ] {
            var rejected = true
            for command in ["info", "reveal"] {
                let result = try runCheckCommand([command, path], suppressError: true)
                rejected = rejected && result.exited && result.status == 1
            }
            checks[name] = rejected
        }
        let directoryArgument = directoryLink.path + "/"
        let linkInfo = try captureCommand(["info", directoryArgument], as: FileInformation.self)
        let linkReveal = try captureCommand(["reveal", directoryArgument], as: FileRevealLocation.self)
        checks["cli_directory_link_with_trailing_slash"] = linkInfo.entry.isDirectory &&
            !linkInfo.entry.isSymbolicLink && linkInfo.symbolicLinkDestination == nil &&
            linkReveal.selectedURL?.hasDirectoryPath == true &&
            linkReveal.selectedURL?.path == directoryLink.path
        return checks
    }

    private static func captureCommand<T: Decodable>(_ arguments: [String], as type: T.Type) throws -> T {
        let result = try runCheckCommand(arguments)
        guard result.exited, result.status == 0 else { throw CommandError.checkFailed }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: result.data)
    }

    private static func runCheckCommand(_ arguments: [String], suppressError: Bool = false) throws
        -> (exited: Bool, status: Int32, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = suppressError ? FileHandle.nullDevice : FileHandle.standardError
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationReason == .exit, process.terminationStatus, data)
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
