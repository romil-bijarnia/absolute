import Foundation

/// Return values observed for the supported owned-namespace operations.
public enum MachReturnCode: Int32, Codable, Sendable {
    case success = 0
    case invalidName = 15
    case invalidRight = 17
    case sendInvalidDestination = 0x1000_0003
    case sendTimedOut = 0x1000_0004
    case sendMessageTooSmall = 0x1000_0008
    case sendInvalidHeader = 0x1000_0010
    case receiveInvalidName = 0x1000_4002
    case receiveTimedOut = 0x1000_4003
    case receiveTooLarge = 0x1000_4004
}

/// Unsupported features and implementation bounds are distinct from Mach errors.
public enum MachCompatibilityError: Error, Equatable, Sendable {
    case unsupportedHeader
    case unsupportedDisposition(UInt32)
    case invalidBufferExtent
    case unsupportedReceiveCapacity(Int)
    case unsupportedQueueLimit(Int)
    case resourceLimit
}

public struct MachSendResult: Equatable, Sendable {
    public let status: MachReturnCode
    /// A failed send can return an owned right and rewrite the disposition.
    public let returnedBuffer: Data
}

public struct MachReceiveResult: Equatable, Sendable {
    public let status: MachReturnCode
    /// Only the header/message and returned default trailer, without unused space.
    /// Error buffers can contain a size larger than the bytes actually returned.
    public let buffer: Data
    public let trailer: Data?
}

public struct MachPortState: Equatable, Sendable {
    public let status: MachReturnCode
    public let type: UInt32
    public let sendReferences: UInt32
    public let receiveReferences: UInt32
    public let deadNameReferences: UInt32
    public let queueStatus: MachReturnCode
    public let queueCount: Int
    public let queueLimit: Int
}

/// Portable in-process namespace for the measured nonblocking inline-message subset.
///
/// Names belong only to this instance. This does not expose kernel ports, isolate
/// other processes, implement traps, or transfer descriptors/vouchers/reply rights.
/// Each operation is serialized; positive waits and port sets are not implemented.
public actor MachPortSpace {
    private struct QueuedMessage {
        let id: Int32
        let payload: Data
        var size: Int { MachMessageHeader.byteCount + payload.count }
    }
    private struct Port {
        var receive = true
        var sendReferences: UInt32 = 0
        var deadReferences: UInt32 = 0
        var queueLimit = 5
        var messages: [QueuedMessage] = []
    }
    private var ports: [UInt32: Port] = [:]
    private var nextName: UInt32 = 1
    private var queuedBytes = 0
    private let maximumNames = 4_096
    private let maximumMessageBytes = 1_048_576
    private let maximumQueuedBytes = 16_777_216
    private static let defaultTrailer = Data([0, 0, 0, 0, 8, 0, 0, 0])

    public init() {}

    public func allocateReceiveRight() throws -> UInt32 {
        guard ports.count < maximumNames, nextName < UInt32.max else {
            throw MachCompatibilityError.resourceLimit
        }
        let name = nextName
        nextName += 1
        ports[name] = Port()
        return name
    }

    public func insertSendRight(_ name: UInt32) throws -> MachReturnCode {
        guard var port = ports[name] else { return .invalidName }
        guard port.receive else { return .invalidRight }
        guard port.sendReferences < UInt32.max else { throw MachCompatibilityError.resourceLimit }
        port.sendReferences += 1
        ports[name] = port
        return .success
    }

    public func setQueueLimit(_ name: UInt32, limit: Int) throws -> MachReturnCode {
        // Bounds for this component, not a claim about all native limit settings.
        guard (1...1_024).contains(limit) else { throw MachCompatibilityError.unsupportedQueueLimit(limit) }
        guard var port = ports[name], port.receive else { return .invalidName }
        port.queueLimit = limit
        ports[name] = port
        return .success
    }

    public func state(of name: UInt32) -> MachPortState {
        guard let port = ports[name] else {
            return MachPortState(status: .invalidName, type: 0, sendReferences: 0,
                receiveReferences: 0, deadNameReferences: 0, queueStatus: .invalidName,
                queueCount: 0, queueLimit: 0)
        }
        let type: UInt32 = (port.receive ? 0x0002_0000 : 0)
            | (port.sendReferences > 0 ? 0x0001_0000 : 0)
            | (port.deadReferences > 0 ? 0x0010_0000 : 0)
        return MachPortState(status: .success, type: type, sendReferences: port.sendReferences,
            receiveReferences: port.receive ? 1 : 0, deadNameReferences: port.deadReferences,
            queueStatus: port.receive ? .success : .invalidName,
            queueCount: port.receive ? port.messages.count : 0,
            queueLimit: port.receive ? port.queueLimit : 0)
    }

    /// Matches the supported mach_msg send_size convention independently of header.size.
    /// The operation is a zero-timeout send; callers must use the returned buffer
    /// when retrying a failed COPY_SEND, whose copied right is returned as MOVE_SEND.
    public func send(_ buffer: Data, sendSize: Int? = nil) throws -> MachSendResult {
        let size = sendSize ?? buffer.count
        guard size >= 0, size <= buffer.count else { throw MachCompatibilityError.invalidBufferExtent }
        guard size >= MachMessageHeader.byteCount, size.isMultiple(of: 4) else {
            return MachSendResult(status: .sendMessageTooSmall, returnedBuffer: buffer)
        }
        guard size <= maximumMessageBytes else { throw MachCompatibilityError.resourceLimit }
        let header = try MachMessageHeader.decode(buffer)
        guard header.otherBits == 0, header.localDisposition == 0,
              header.voucherDisposition == 0, header.localPort == 0, header.voucherPort == 0 else {
            throw MachCompatibilityError.unsupportedHeader
        }
        let disposition = header.remoteDisposition
        if disposition == 0 || disposition == 16 {
            return MachSendResult(status: .sendInvalidHeader, returnedBuffer: buffer)
        }
        guard disposition == 17 || disposition == 19 else {
            throw MachCompatibilityError.unsupportedDisposition(disposition)
        }
        guard var port = ports[header.remotePort], port.receive, port.sendReferences > 0 else {
            return MachSendResult(status: .sendInvalidDestination, returnedBuffer: buffer)
        }
        if port.messages.count >= port.queueLimit {
            if disposition == 19 {
                guard port.sendReferences < UInt32.max else { throw MachCompatibilityError.resourceLimit }
                // Native error copy-out returns the copied right to this namespace.
                port.sendReferences += 1
            }
            let returnedHeader = MachMessageHeader(
                bits: MachMessageHeader.makeBits(remote: 17), size: UInt32(size),
                remotePort: header.remotePort, id: header.id
            )
            var returned = returnedHeader.encode()
            returned.append(buffer.suffix(buffer.count - MachMessageHeader.byteCount))
            ports[header.remotePort] = port
            return MachSendResult(status: .sendTimedOut, returnedBuffer: returned)
        }
        guard queuedBytes <= maximumQueuedBytes - size else { throw MachCompatibilityError.resourceLimit }
        let start = buffer.index(buffer.startIndex, offsetBy: MachMessageHeader.byteCount)
        let end = buffer.index(buffer.startIndex, offsetBy: size)
        port.messages.append(QueuedMessage(id: header.id, payload: Data(buffer[start..<end])))
        if disposition == 17 { port.sendReferences -= 1 }
        queuedBytes += size
        ports[header.remotePort] = port
        return MachSendResult(status: .success, returnedBuffer: buffer)
    }

    /// Receives into a fresh zeroed-header view with the default eight-byte trailer.
    /// keepTooLarge corresponds only to the observed MACH_RCV_LARGE behavior.
    public func receive(_ name: UInt32, capacity: Int, keepTooLarge: Bool = false) throws -> MachReceiveResult {
        guard capacity >= MachMessageHeader.byteCount else {
            throw MachCompatibilityError.unsupportedReceiveCapacity(capacity)
        }
        let empty = Data(repeating: 0, count: MachMessageHeader.byteCount)
        guard var port = ports[name], port.receive else {
            return MachReceiveResult(status: .receiveInvalidName, buffer: empty, trailer: nil)
        }
        guard let message = port.messages.first else {
            return MachReceiveResult(status: .receiveTimedOut, buffer: empty, trailer: nil)
        }
        if message.size + Self.defaultTrailer.count > capacity, keepTooLarge {
            let partial = MachMessageHeader(size: UInt32(message.size)).encode()
            return MachReceiveResult(status: .receiveTooLarge, buffer: partial, trailer: nil)
        }
        port.messages.removeFirst()
        queuedBytes -= message.size
        ports[name] = port
        let fits = message.size + Self.defaultTrailer.count <= capacity
        let size = fits ? message.size : MachMessageHeader.byteCount
        let header = MachMessageHeader(
            bits: MachMessageHeader.makeBits(remote: 0, local: 17),
            size: UInt32(size), localPort: name, id: message.id
        )
        var bytes = header.encode()
        if fits { bytes.append(message.payload) }
        let trailer = capacity >= size + Self.defaultTrailer.count ? Self.defaultTrailer : nil
        if let trailer { bytes.append(trailer) }
        return MachReceiveResult(status: fits ? .success : .receiveTooLarge, buffer: bytes, trailer: trailer)
    }

    public func releaseReceiveRight(_ name: UInt32) -> MachReturnCode {
        guard var port = ports[name] else { return .invalidName }
        guard port.receive else { return .invalidRight }
        queuedBytes -= port.messages.reduce(0) { $0 + $1.size }
        port.messages.removeAll()
        port.receive = false
        port.deadReferences = port.sendReferences
        port.sendReferences = 0
        if port.deadReferences == 0 { ports.removeValue(forKey: name) }
        else { ports[name] = port }
        return .success
    }

    /// Releases one send or dead-name reference, preserving a remaining receive right.
    public func deallocateNameReference(_ name: UInt32) -> MachReturnCode {
        guard var port = ports[name] else { return .invalidName }
        if port.sendReferences > 0 { port.sendReferences -= 1 }
        else if port.deadReferences > 0 { port.deadReferences -= 1 }
        else { return .invalidRight }
        if !port.receive && port.sendReferences == 0 && port.deadReferences == 0 {
            ports.removeValue(forKey: name)
        } else { ports[name] = port }
        return .success
    }
}
