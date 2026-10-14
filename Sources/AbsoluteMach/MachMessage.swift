import Foundation

/// Bounds errors for the inline Mach message layout.
public enum MachMessageError: Error, Equatable, Sendable {
    case truncatedHeader(actual: Int)
    case invalidMessageSize(UInt32)
    case truncatedMessage(declaredSize: UInt32, actual: Int)
    case sizeMismatch(declaredSize: UInt32, actualSize: UInt32)
    case payloadTooLarge(actual: Int)
}

/// The 24-byte user-space Mach message header used by the inspected ARM64 macOS ABI.
///
/// This codec always uses little-endian byte order. Port values are names in a
/// task's namespace; encoding or decoding them does not create or transfer rights.
public struct MachMessageHeader: Equatable, Sendable {
    public static let byteCount = 24
    public static let complexBit: UInt32 = 0x8000_0000

    private static let dispositionMask: UInt32 = 0x1f
    private static let portsMask: UInt32 = 0x001f_1f1f

    public let bits: UInt32
    public let size: UInt32
    public let remotePort: UInt32
    public let localPort: UInt32
    public let voucherPort: UInt32
    public let id: Int32

    public init(
        bits: UInt32 = 0,
        size: UInt32 = 24,
        remotePort: UInt32 = 0,
        localPort: UInt32 = 0,
        voucherPort: UInt32 = 0,
        id: Int32 = 0
    ) {
        self.bits = bits
        self.size = size
        self.remotePort = remotePort
        self.localPort = localPort
        self.voucherPort = voucherPort
        self.id = id
    }

    public var remoteDisposition: UInt32 { bits & Self.dispositionMask }
    public var localDisposition: UInt32 { (bits >> 8) & Self.dispositionMask }
    public var voucherDisposition: UInt32 { (bits >> 16) & Self.dispositionMask }
    public var otherBits: UInt32 { bits & ~Self.portsMask }
    public var isComplex: Bool { bits & Self.complexBit != 0 }

    /// Packs the low five bits of each disposition and preserves non-port bits.
    /// Disposition numbers and reserved bits are not validated against kernel policy.
    public static func makeBits(
        remote: UInt32,
        local: UInt32 = 0,
        voucher: UInt32 = 0,
        otherBits: UInt32 = 0
    ) -> UInt32 {
        (remote & dispositionMask)
            | ((local & dispositionMask) << 8)
            | ((voucher & dispositionMask) << 16)
            | (otherBits & ~portsMask)
    }

    /// Encodes the raw fields, including an unvalidated declared message size.
    public func encode() -> Data {
        var bytes = Data(capacity: Self.byteCount)
        for word in [bits, size, remotePort, localPort, voucherPort, UInt32(bitPattern: id)] {
            bytes.append(UInt8(truncatingIfNeeded: word))
            bytes.append(UInt8(truncatingIfNeeded: word >> 8))
            bytes.append(UInt8(truncatingIfNeeded: word >> 16))
            bytes.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return bytes
    }

    /// Reads the first 24 bytes, without validating the declared body size.
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count >= byteCount else {
            throw MachMessageError.truncatedHeader(actual: bytes.count)
        }
        return Self(
            bits: readWord(bytes, offset: 0),
            size: readWord(bytes, offset: 4),
            remotePort: readWord(bytes, offset: 8),
            localPort: readWord(bytes, offset: 12),
            voucherPort: readWord(bytes, offset: 16),
            id: Int32(bitPattern: readWord(bytes, offset: 20))
        )
    }

    private static func readWord(_ bytes: Data, offset: Int) -> UInt32 {
        var word: UInt32 = 0
        for byteOffset in 0..<4 {
            let index = bytes.index(bytes.startIndex, offsetBy: offset + byteOffset)
            word |= UInt32(bytes[index]) << (byteOffset * 8)
        }
        return word
    }
}

/// A bounded Mach message header and its opaque inline body.
///
/// This is a layout codec, not a Mach IPC implementation or a kernel-validity
/// check. Complex-message descriptor bytes are preserved without interpretation;
/// out-of-line memory and the rights named by ports are not represented here.
public struct MachMessage: Equatable, Sendable {
    public let header: MachMessageHeader
    public let payload: Data

    /// All received bytes after `header.size`, excluded from `payload`.
    /// These may include alignment padding, a receive trailer, or unused buffer
    /// space. Their structure and validity are not inferred by this codec.
    public let trailingBytes: Data

    /// Creates a message whose declared size must match its header and payload.
    public init(header: MachMessageHeader, payload: Data, trailingBytes: Data = Data()) throws {
        guard header.size >= UInt32(MachMessageHeader.byteCount) else {
            throw MachMessageError.invalidMessageSize(header.size)
        }
        let actualSize = try Self.messageSize(payloadCount: payload.count)
        guard header.size == actualSize else {
            throw MachMessageError.sizeMismatch(declaredSize: header.size, actualSize: actualSize)
        }
        self.header = header
        self.payload = payload
        self.trailingBytes = trailingBytes
    }

    /// Creates an inline message, computing the declared size from its payload.
    public init(
        bits: UInt32 = 0,
        remotePort: UInt32 = 0,
        localPort: UInt32 = 0,
        voucherPort: UInt32 = 0,
        id: Int32 = 0,
        payload: Data = Data()
    ) throws {
        self.header = MachMessageHeader(
            bits: bits,
            size: try Self.messageSize(payloadCount: payload.count),
            remotePort: remotePort,
            localPort: localPort,
            voucherPort: voucherPort,
            id: id
        )
        self.payload = payload
        self.trailingBytes = Data()
    }

    /// Decodes one message from a receive buffer using the declared message size.
    /// Bytes beyond that size are retained separately, including any padding.
    public static func decode(_ bytes: Data) throws -> Self {
        let header = try MachMessageHeader.decode(bytes)
        guard header.size >= UInt32(MachMessageHeader.byteCount) else {
            throw MachMessageError.invalidMessageSize(header.size)
        }
        guard let size = Int(exactly: header.size), size <= bytes.count else {
            throw MachMessageError.truncatedMessage(declaredSize: header.size, actual: bytes.count)
        }
        let payloadStart = bytes.index(bytes.startIndex, offsetBy: MachMessageHeader.byteCount)
        let messageEnd = bytes.index(bytes.startIndex, offsetBy: size)
        return try Self(
            header: header,
            payload: Data(bytes[payloadStart..<messageEnd]),
            trailingBytes: Data(bytes[messageEnd..<bytes.endIndex])
        )
    }

    /// Encodes the message only, or reconstructs the received buffer when requested.
    /// Trailing bytes never contribute to the header's declared message size.
    public func encode(includeTrailingBytes: Bool = false) -> Data {
        var bytes = header.encode()
        bytes.append(payload)
        if includeTrailingBytes {
            bytes.append(trailingBytes)
        }
        return bytes
    }

    private static func messageSize(payloadCount: Int) throws -> UInt32 {
        let headerSize = UInt32(MachMessageHeader.byteCount)
        guard let payloadSize = UInt32(exactly: payloadCount), payloadSize <= UInt32.max - headerSize else {
            throw MachMessageError.payloadTooLarge(actual: payloadCount)
        }
        return headerSize + payloadSize
    }
}
