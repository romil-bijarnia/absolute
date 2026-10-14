import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// Selects whether to inspect the final directory entry or resolve its target.
public enum FileResolutionPolicy: String, Codable, Sendable {
    case noFollow, follow
}

public enum FileResolutionStatus: String, Codable, Sendable {
    case notFollowed, resolved, notFound, notDirectory, symbolicLinkLoop, permissionDenied, ioError
}

/// A link's stored destination and successful resolution are different facts.
/// Only a successful follow operation supplies a resolvedURL.
public struct FileResolution: Codable, Equatable, Sendable {
    public let entryURL: URL
    public let policy: FileResolutionPolicy
    public let status: FileResolutionStatus
    public let resolvedURL: URL?
    public let symbolicLinkDestination: String?
    public let posixErrorCode: Int32?
}

enum FilePathResolver {
    static func fileSystemPath(for url: URL) -> String {
        // Foundation strips a trailing slash from both path and its unsafe
        // filesystem representation. The URL still records that the final
        // component must name a directory; preserve that requirement for POSIX.
        let path = url.path
        return url.hasDirectoryPath && !path.hasSuffix("/") ? path + "/" : path
    }

    static func resolve(_ url: URL, policy: FileResolutionPolicy) -> FileResolution {
        let path = fileSystemPath(for: url)
        var metadata = stat()
        let inspectionError: Int32? = path.withCString {
            lstat($0, &metadata) == 0 ? nil : errno
        }
        if let inspectionError {
            return failure(url, policy: policy, destination: nil, code: inspectionError)
        }

        var destination: String?
        if metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
            do {
                destination = try FileManager.default.destinationOfSymbolicLink(atPath: path)
            } catch {
                let error = error as NSError
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                let code = [error, underlying].compactMap { $0 }
                    .first { $0.domain == NSPOSIXErrorDomain }
                    .flatMap { Int32(exactly: $0.code) }
                return failure(url, policy: policy, destination: nil, code: code)
            }
        }

        if policy == .noFollow {
            return FileResolution(entryURL: url, policy: policy, status: .notFollowed,
                resolvedURL: nil, symbolicLinkDestination: destination, posixErrorCode: nil)
        }

        // Pass the original path to the filesystem: collapsing a link/.. pair
        // before traversal can identify an entirely different file.
        let resolution = path.withCString { path -> (UnsafeMutablePointer<CChar>?, Int32) in
            let resolved = realpath(path, nil)
            return (resolved, resolved == nil ? errno : 0)
        }
        guard let resolved = resolution.0 else {
            return failure(url, policy: policy, destination: destination, code: resolution.1)
        }
        defer { free(resolved) }
        let target = URL(fileURLWithFileSystemRepresentation: resolved, isDirectory: false, relativeTo: nil)
        return FileResolution(entryURL: url, policy: policy, status: .resolved,
            resolvedURL: target, symbolicLinkDestination: destination, posixErrorCode: nil)
    }

    private static func failure(_ url: URL, policy: FileResolutionPolicy,
                                destination: String?, code: Int32?) -> FileResolution {
        let status: FileResolutionStatus
        switch code {
        case ENOENT: status = .notFound
        case ENOTDIR: status = .notDirectory
        case ELOOP: status = .symbolicLinkLoop
        case EACCES, EPERM: status = .permissionDenied
        default: status = .ioError
        }
        return FileResolution(entryURL: url, policy: policy, status: status,
            resolvedURL: nil, symbolicLinkDestination: destination, posixErrorCode: code)
    }
}
