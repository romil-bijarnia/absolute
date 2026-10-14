import Foundation
import XCTest
import AbsoluteMach

#if os(macOS)
import Darwin
#endif

final class MachMessageTests: XCTestCase {
    // A 27-byte message with three opaque payload bytes. The macOS-only test
    // below checks its header against a locally constructed SDK C structure.
    private let fixture = Data([
        0x13, 0x15, 0x14, 0x80,
        0x1b, 0x00, 0x00, 0x00,
        0x44, 0x33, 0x22, 0x11,
        0x88, 0x77, 0x66, 0x55,
        0xcc, 0xbb, 0xaa, 0x99,
        0x79, 0x29, 0xed, 0xff,
        0xa7, 0x00, 0xff
    ])

    func testDecodesIndependentByteFixture() throws {
        let message = try MachMessage.decode(fixture)
        XCTAssertEqual(message.header.bits, 0x8014_1513)
        XCTAssertEqual(message.header.size, 27)
        XCTAssertEqual(message.header.remotePort, 0x1122_3344)
        XCTAssertEqual(message.header.localPort, 0x5566_7788)
        XCTAssertEqual(message.header.voucherPort, 0x99aa_bbcc)
        XCTAssertEqual(message.header.id, -1_234_567)
        XCTAssertEqual(message.payload, Data([0xa7, 0x00, 0xff]))
        XCTAssertTrue(message.trailingBytes.isEmpty)
    }

    func testEncodesIndependentByteFixtureAndComputesSize() throws {
        let message = try MachMessage(
            bits: 0x8014_1513,
            remotePort: 0x1122_3344,
            localPort: 0x5566_7788,
            voucherPort: 0x99aa_bbcc,
            id: -1_234_567,
            payload: Data([0xa7, 0x00, 0xff])
        )
        XCTAssertEqual(message.header.size, 27)
        XCTAssertEqual(message.header.encode(), fixture.prefix(24))
        XCTAssertEqual(message.encode(), fixture)
    }

    func testHeaderOnlyMessage() throws {
        let message = try MachMessage(id: 42)
        XCTAssertEqual(message.header.size, 24)
        XCTAssertEqual(message.encode().count, 24)
        XCTAssertTrue(message.payload.isEmpty)
        XCTAssertTrue(message.trailingBytes.isEmpty)
        XCTAssertEqual(try MachMessage.decode(message.encode()), message)
    }

    func testRejectsEveryTruncatedHeaderLength() {
        for count in 0..<24 {
            let bytes = Data(fixture.prefix(count))
            XCTAssertThrowsError(try MachMessageHeader.decode(bytes)) { error in
                XCTAssertEqual(error as? MachMessageError, .truncatedHeader(actual: count))
            }
            XCTAssertThrowsError(try MachMessage.decode(bytes)) { error in
                XCTAssertEqual(error as? MachMessageError, .truncatedHeader(actual: count))
            }
        }
    }

    func testRejectsDeclaredSizesSmallerThanHeader() {
        for size in [UInt8(0), 1, 23] {
            var bytes = fixture
            bytes[4] = size
            XCTAssertThrowsError(try MachMessage.decode(bytes)) { error in
                XCTAssertEqual(error as? MachMessageError, .invalidMessageSize(UInt32(size)))
            }
        }
    }

    func testRejectsEveryTruncatedPayloadLength() {
        for count in 24..<27 {
            XCTAssertThrowsError(try MachMessage.decode(Data(fixture.prefix(count)))) { error in
                XCTAssertEqual(error as? MachMessageError, .truncatedMessage(declaredSize: 27, actual: count))
            }
        }
    }

    func testRejectsMaximumDeclaredSizeWithoutAllocatingFromIt() {
        var bytes = Data(fixture.prefix(24))
        bytes.replaceSubrange(4..<8, with: [0xff, 0xff, 0xff, 0xff])
        XCTAssertThrowsError(try MachMessage.decode(bytes)) { error in
            XCTAssertEqual(error as? MachMessageError, .truncatedMessage(declaredSize: .max, actual: 24))
        }
    }

    func testKeepsPaddingAndTrailerOutsidePayload() throws {
        // One alignment byte followed by an eight-byte format-0 trailer.
        let trailing = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00])
        let received = fixture + trailing
        let message = try MachMessage.decode(received)
        XCTAssertEqual(message.header.size, 27)
        XCTAssertEqual(message.payload, Data([0xa7, 0x00, 0xff]))
        XCTAssertEqual(message.trailingBytes, trailing)
        XCTAssertEqual(message.encode(), fixture)
        XCTAssertEqual(message.encode(includeTrailingBytes: true), received)
    }

    func testPreservesArbitraryTrailingBytesWithoutParsingThem() throws {
        let trailing = Data([0xff, 0xfe, 0xfd])
        let message = try MachMessage.decode(fixture + trailing)
        XCTAssertEqual(message.trailingBytes, trailing)
        XCTAssertEqual(message.encode(includeTrailingBytes: true), fixture + trailing)
    }

    func testDecodesSlicedDataWithNonzeroStartIndex() throws {
        let trailing = Data([0xaa, 0xbb])
        let buffer = Data([0xff, 0xee, 0xdd]) + fixture + trailing + Data([0xcc])
        let slice = buffer[3..<(buffer.count - 1)]
        XCTAssertEqual(slice.startIndex, 3)
        XCTAssertEqual(try MachMessageHeader.decode(slice).remotePort, 0x1122_3344)
        let message = try MachMessage.decode(slice)
        XCTAssertEqual(message.payload, Data([0xa7, 0x00, 0xff]))
        XCTAssertEqual(message.trailingBytes, trailing)
        XCTAssertEqual(message.encode(includeTrailingBytes: true), fixture + trailing)
    }

    func testEncodesSlicedPayloadAndTrailingData() throws {
        let bytes = Data([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
        let message = try MachMessage(
            header: MachMessageHeader(size: 27),
            payload: bytes[1..<4],
            trailingBytes: bytes[4..<6]
        )
        XCTAssertEqual(message.encode().suffix(3), Data([0xbb, 0xcc, 0xdd]))
        XCTAssertEqual(message.encode(includeTrailingBytes: true).suffix(5), Data([0xbb, 0xcc, 0xdd, 0xee, 0xff]))
    }

    func testSignedMessageIDBoundariesHaveExactBytes() throws {
        let cases: [(Int32, [UInt8])] = [
            (.min, [0x00, 0x00, 0x00, 0x80]),
            (-1, [0xff, 0xff, 0xff, 0xff]),
            (0, [0x00, 0x00, 0x00, 0x00]),
            (1, [0x01, 0x00, 0x00, 0x00]),
            (.max, [0xff, 0xff, 0xff, 0x7f])
        ]
        for (id, idBytes) in cases {
            let header = MachMessageHeader(id: id)
            XCTAssertEqual(header.encode().suffix(4), Data(idBytes))
            var bytes = Data(fixture.prefix(24))
            bytes.replaceSubrange(20..<24, with: idBytes)
            XCTAssertEqual(try MachMessageHeader.decode(bytes).id, id)
        }
    }

    func testDispositionFieldsAndComplexFlag() throws {
        let header = try MachMessageHeader.decode(fixture)
        XCTAssertEqual(header.remoteDisposition, 19)
        XCTAssertEqual(header.localDisposition, 21)
        XCTAssertEqual(header.voucherDisposition, 20)
        XCTAssertEqual(header.otherBits, 0x8000_0000)
        XCTAssertTrue(header.isComplex)
        XCTAssertFalse(MachMessageHeader(bits: 0x001f_1f1f).isComplex)
        XCTAssertEqual(
            MachMessageHeader.makeBits(
                remote: 19,
                local: 21,
                voucher: 20,
                otherBits: MachMessageHeader.complexBit
            ),
            0x8014_1513
        )
    }

    func testDispositionConstructionMasksFieldsAndReplacesOtherPortBits() {
        XCTAssertEqual(
            MachMessageHeader.makeBits(
                remote: 0x33,
                local: 0x35,
                voucher: 0x34,
                otherBits: 0x801f_1f1f
            ),
            0x8014_1513
        )
        let header = MachMessageHeader(bits: .max)
        XCTAssertEqual(header.remoteDisposition, 31)
        XCTAssertEqual(header.localDisposition, 31)
        XCTAssertEqual(header.voucherDisposition, 31)
        XCTAssertEqual(header.otherBits, 0xffe0_e0e0)
        XCTAssertEqual(MachMessageHeader.makeBits(remote: 0, otherBits: .max), 0xffe0_e0e0)
    }

    func testRawHeaderPreservesReservedBitsAndUnvalidatedSize() throws {
        let header = MachMessageHeader(bits: .max, size: 0, remotePort: .max, id: .min)
        XCTAssertEqual(try MachMessageHeader.decode(header.encode()), header)
    }

    func testConstructionRejectsInconsistentSizes() {
        XCTAssertThrowsError(try MachMessage(header: MachMessageHeader(size: 23), payload: Data())) { error in
            XCTAssertEqual(error as? MachMessageError, .invalidMessageSize(23))
        }
        XCTAssertThrowsError(try MachMessage(header: MachMessageHeader(size: 25), payload: Data())) { error in
            XCTAssertEqual(error as? MachMessageError, .sizeMismatch(declaredSize: 25, actualSize: 24))
        }
        XCTAssertThrowsError(try MachMessage(header: MachMessageHeader(size: 24), payload: Data([0x01]))) { error in
            XCTAssertEqual(error as? MachMessageError, .sizeMismatch(declaredSize: 24, actualSize: 25))
        }
    }

    func testComplexBodyIsOpaqueAndDoesNotTriggerDescriptorParsing() throws {
        // This body is not a valid descriptor list. A layout codec preserves it.
        let body = Data([0xff, 0xff, 0xff, 0xff])
        let message = try MachMessage(bits: MachMessageHeader.complexBit, payload: body)
        XCTAssertEqual(try MachMessage.decode(message.encode()).payload, body)
    }

    #if os(macOS)
    func testFixtureMatchesInstalledSDKNativeHeaderLayout() throws {
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.size, 24)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_bits), 0)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_size), 4)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_remote_port), 8)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_local_port), 12)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_voucher_port), 16)
        XCTAssertEqual(MemoryLayout<mach_msg_header_t>.offset(of: \.msgh_id), 20)
        let nativeHeader = mach_msg_header_t(
            msgh_bits: 0x8014_1513,
            msgh_size: 27,
            msgh_remote_port: 0x1122_3344,
            msgh_local_port: 0x5566_7788,
            msgh_voucher_port: 0x99aa_bbcc,
            msgh_id: -1_234_567
        )
        let nativeBytes = withUnsafeBytes(of: nativeHeader) { Data($0) }
        XCTAssertEqual(nativeBytes, fixture.prefix(24))
        XCTAssertEqual(try MachMessageHeader.decode(nativeBytes).id, nativeHeader.msgh_id)
    }
    #endif
}
