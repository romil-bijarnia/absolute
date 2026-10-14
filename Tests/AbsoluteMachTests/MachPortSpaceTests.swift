import Foundation
import XCTest
import AbsoluteMach

@MainActor
final class MachPortSpaceTests: XCTestCase {
    func testReplaysNativeReferenceScenarios() async throws {
        let reference = try loadReference().oracle
        XCTAssertEqual(reference.schema, 1)
        XCTAssertTrue(reference.passed)
        XCTAssertEqual(reference.scenarioCount, reference.scenarios.count)
        XCTAssertEqual(reference.checkCount, reference.scenarios.reduce(0) { $0 + $1.checkCount })
        XCTAssertEqual(reference.abi.headerBytes, MachMessageHeader.byteCount)
        XCTAssertEqual(reference.abi.portNameBytes, MemoryLayout<UInt32>.size)
        XCTAssertFalse(reference.scenarios.isEmpty)
        XCTAssertEqual(Set(reference.scenarios.map(\.name)).count, reference.scenarios.count)

        for scenario in reference.scenarios {
            do {
                try await replay(scenario, abi: reference.abi)
            } catch {
                XCTFail("\(scenario.name): replay failed: \(error)")
            }
        }
    }

    func testReferenceIdentifiesItsNativeEvidence() throws {
        let reference = try loadReference()
        XCTAssertEqual(reference.schema, 1)
        XCTAssertTrue(reference.evidenceId.hasPrefix("absolute-mach-messages-sha256:"))
        let digest = try XCTUnwrap(reference.evidenceId.split(separator: ":").last)
        XCTAssertEqual(try decodeHex(String(digest)).count, 32)
        XCTAssertEqual(reference.evidenceType, "owned-process-runtime-reference")
        XCTAssertGreaterThanOrEqual(reference.repeatability.runs, 2)
        XCTAssertTrue(reference.repeatability.identical)
        XCTAssertTrue(reference.repeatability.allChecksPassed)
        XCTAssertFalse(reference.provenance.source.file.isEmpty)
        XCTAssertEqual(try decodeHex(reference.provenance.source.sha256).count, 32)
        XCTAssertFalse(reference.provenance.headers.isEmpty)
        for header in reference.provenance.headers {
            XCTAssertFalse(header.file.isEmpty)
            XCTAssertEqual(try decodeHex(header.sha256).count, 32)
        }
    }

    func testReplayMapsTokensToDifferentAllocatedNames() async throws {
        let reference = try loadReference().oracle
        for scenario in reference.scenarios {
            do {
                try await replay(scenario, abi: reference.abi, reservedNames: 3)
            } catch {
                XCTFail("\(scenario.name): remapped replay failed: \(error)")
            }
        }
    }

    func testUnsupportedRequestsLeaveTheNamespaceUnchanged() async throws {
        let space = MachPortSpace()
        let name = try await space.allocateReceiveRight()
        let inserted = try await space.insertSendRight(name)
        XCTAssertEqual(inserted, .success)
        let before = await space.state(of: name)

        let unsupportedHeaders = [
            MachMessageHeader(bits: 19 | MachMessageHeader.complexBit, remotePort: name),
            MachMessageHeader(bits: 19 | 0x2000_0000, remotePort: name),
            MachMessageHeader(bits: MachMessageHeader.makeBits(remote: 19, local: 17), remotePort: name),
            MachMessageHeader(bits: 19, remotePort: name, localPort: name),
            MachMessageHeader(bits: MachMessageHeader.makeBits(remote: 19, voucher: 17), remotePort: name),
            MachMessageHeader(bits: 19, remotePort: name, voucherPort: name)
        ]
        for header in unsupportedHeaders {
            await assertRejected(.unsupportedHeader) {
                _ = try await space.send(header.encode())
            }
        }
        await assertRejected(.unsupportedDisposition(20)) {
            _ = try await space.send(MachMessageHeader(bits: 20, remotePort: name).encode())
        }
        let message = try MachMessage(bits: 19, remotePort: name).encode()
        for extent in [-1, message.count + 1] {
            await assertRejected(.invalidBufferExtent) {
                _ = try await space.send(message, sendSize: extent)
            }
        }
        await assertRejected(.unsupportedReceiveCapacity(23)) {
            _ = try await space.receive(name, capacity: 23)
        }
        for limit in [0, 1_025] {
            await assertRejected(.unsupportedQueueLimit(limit)) {
                _ = try await space.setQueueLimit(name, limit: limit)
            }
        }
        let after = await space.state(of: name)
        XCTAssertEqual(after, before)
    }

    private func replay(_ scenario: ReferenceScenario, abi: ReferenceABI, reservedNames: Int = 0) async throws {
        let space = MachPortSpace()
        // Unrelated receive rights force fixture tokens and allocated names to
        // differ, exercising the adapter without changing any scenario's rights.
        for _ in 0..<reservedNames {
            _ = try await space.allocateReceiveRight()
        }
        var roleNames: [String: UInt32] = ["null": 0, "dead": .max]
        var tokenNames: [UInt32: UInt32] = [0: 0, .max: .max]
        var nameTokens = tokenNames
        var checks = 0
        XCTAssertTrue(scenario.passed, scenario.name)

        for (sequence, operation) in scenario.operations.enumerated() {
            let context = "\(scenario.name) [\(operation.sequence)] \(operation.operation) \(operation.label ?? operation.name ?? "")"
            XCTAssertEqual(operation.sequence, sequence, context)

            switch operation.operation {
            case "allocate_receive":
                let role = try XCTUnwrap(operation.role, context)
                let token = try XCTUnwrap(operation.token, context)
                XCTAssertNil(roleNames[role], context)
                XCTAssertNil(tokenNames[token], context)
                let name = try await space.allocateReceiveRight()
                roleNames[role] = name
                tokenNames[token] = name
                nameTokens[name] = token
                XCTAssertEqual(MachReturnCode.success.rawValue, operation.status, context)

            case "insert_make_send":
                let name = try mappedName(operation.role, roles: roleNames, context: context)
                let status = try await space.insertSendRight(name)
                XCTAssertEqual(status.rawValue, operation.status, context)

            case "set_queue_limit":
                let name = try mappedName(operation.role, roles: roleNames, context: context)
                let limit = try XCTUnwrap(operation.limit, context)
                let status = try await space.setQueueLimit(name, limit: limit)
                XCTAssertEqual(status.rawValue, operation.status, context)

            case "send":
                XCTAssertEqual(operation.timeoutMs, 0, context)
                let before = try XCTUnwrap(operation.before, context)
                let after = try XCTUnwrap(operation.after, context)
                let captured = try decodeHex(before.normalizedBytes)
                let input = try remapPorts(captured, names: tokenNames, offsets: abi.portOffsets, context: context)
                let sendSize = try XCTUnwrap(operation.sendSize, context)
                let result = try await space.send(input, sendSize: sendSize)
                XCTAssertEqual(result.status.rawValue, operation.status, context)
                try assertMessage(result.returnedBuffer, matches: after, roles: roleNames,
                    tokens: nameTokens, abi: abi, context: context)

            case "receive":
                XCTAssertEqual(operation.timeoutMs, 0, context)
                let name = try mappedName(operation.role, roles: roleNames, context: context)
                let capacity = try XCTUnwrap(operation.capacity, context)
                let large = try XCTUnwrap(operation.large, context)
                let expected = try XCTUnwrap(operation.message, context)
                let result = try await space.receive(name, capacity: capacity, keepTooLarge: large)
                XCTAssertEqual(result.status.rawValue, operation.status, context)

                let expectedMessage = try decodeHex(expected.normalizedBytes)
                XCTAssertGreaterThanOrEqual(result.buffer.count, expectedMessage.count, context)
                try assertMessage(Data(result.buffer.prefix(expectedMessage.count)), matches: expected,
                    roles: roleNames, tokens: nameTokens, abi: abi, context: context)
                let expectedTrailer = try operation.trailer.map { try decodeHex($0.bytes) }
                XCTAssertEqual(result.trailer, expectedTrailer, context + " trailer")

                // The native zeroed receive buffer records exact output placement,
                // including trailers returned by an error. Unused space is excluded
                // using only the captured message and trailer extents.
                let storage = try decodeHex(try XCTUnwrap(operation.normalizedStoragePrefix64Bytes, context))
                var outputCount = expectedMessage.count
                if let trailer = operation.trailer {
                    let bytes = try XCTUnwrap(expectedTrailer, context)
                    XCTAssertEqual(bytes.count, Int(trailer.size), context)
                    XCTAssertEqual(try word(in: bytes, at: 0), trailer.type, context)
                    XCTAssertEqual(try word(in: bytes, at: 4), trailer.size, context)
                    outputCount = max(outputCount, trailer.offset + bytes.count)
                    XCTAssertEqual(Data(storage.dropFirst(trailer.offset).prefix(bytes.count)), bytes, context)
                }
                XCTAssertLessThanOrEqual(outputCount, storage.count, context)
                let normalized = try remapPorts(result.buffer, names: nameTokens, offsets: abi.portOffsets, context: context)
                XCTAssertEqual(hex(normalized), hex(Data(storage.prefix(outputCount))), context + " complete output")

                let state = await space.state(of: name)
                let queueCount: UInt32? = state.queueStatus == .success
                    ? try XCTUnwrap(UInt32(exactly: state.queueCount), context) : nil
                XCTAssertEqual(queueCount, operation.queueCountAfter, context + " queue_count_after")

            case "cleanup_receive_right", "destroy_receive_right":
                let name = try mappedName(operation.role, roles: roleNames, context: context)
                let status = await space.releaseReceiveRight(name)
                XCTAssertEqual(status.rawValue, operation.status, context)

            case "cleanup_name_reference", "release_dead_name":
                let name = try mappedName(operation.role, roles: roleNames, context: context)
                let status = await space.deallocateNameReference(name)
                XCTAssertEqual(status.rawValue, operation.status, context)

            case "port_state":
                _ = try XCTUnwrap(operation.state, context)

            case "check":
                XCTAssertEqual(operation.passed, true, context)
                checks += 1

            default:
                throw ReferenceError.invalidFixture("Unrecognized operation: \(context)")
            }

            if let expected = operation.state {
                let name = try mappedName(expected.role, roles: roleNames, context: context)
                let actual = await space.state(of: name)
                assertState(actual, matches: expected, context: context)
            }
        }
        XCTAssertEqual(checks, scenario.checkCount, scenario.name)
    }

    private func assertState(_ actual: MachPortState, matches expected: ReferenceState, context: String) {
        // This component exposes one name lookup status for type and references.
        // Compare it against each independently recorded native query status.
        XCTAssertEqual(actual.status.rawValue, expected.typeStatus, context + " type_status")
        XCTAssertEqual(actual.type, expected.type, context + " type")
        XCTAssertEqual(actual.status.rawValue, expected.sendRefsStatus, context + " send_refs_status")
        XCTAssertEqual(actual.sendReferences, expected.sendRefs, context + " send_refs")
        XCTAssertEqual(actual.status.rawValue, expected.receiveRefsStatus, context + " receive_refs_status")
        XCTAssertEqual(actual.receiveReferences, expected.receiveRefs, context + " receive_refs")
        XCTAssertEqual(actual.status.rawValue, expected.deadRefsStatus, context + " dead_refs_status")
        XCTAssertEqual(actual.deadNameReferences, expected.deadRefs, context + " dead_refs")
        XCTAssertEqual(actual.queueStatus.rawValue, expected.queueStatus, context + " queue_status")
        XCTAssertEqual(actual.queueCount, expected.queueCount, context + " queue_count")
        XCTAssertEqual(actual.queueLimit, expected.queueLimit, context + " queue_limit")
    }

    private func assertMessage(
        _ bytes: Data, matches expected: ReferenceMessage, roles: [String: UInt32],
        tokens: [UInt32: UInt32], abi: ReferenceABI, context: String
    ) throws {
        let normalized = try remapPorts(bytes, names: tokens, offsets: abi.portOffsets, context: context)
        XCTAssertEqual(hex(normalized), expected.normalizedBytes, context + " header/body bytes")
        let header = try MachMessageHeader.decode(bytes)
        XCTAssertEqual(header.bits, expected.bits, context + " bits")
        XCTAssertEqual(header.size, expected.size, context + " size")
        XCTAssertEqual(header.id, expected.id, context + " id")
        XCTAssertEqual(header.remoteDisposition, expected.remoteDisposition, context + " remote disposition")
        XCTAssertEqual(header.localDisposition, expected.localDisposition, context + " local disposition")
        XCTAssertEqual(header.remotePort, try mappedName(expected.remoteRole, roles: roles, context: context), context)
        XCTAssertEqual(header.localPort, try mappedName(expected.localRole, roles: roles, context: context), context)
        XCTAssertEqual(header.voucherPort, try mappedName(expected.voucherRole, roles: roles, context: context), context)
    }

    private func mappedName(_ role: String?, roles: [String: UInt32], context: String) throws -> UInt32 {
        let role = try XCTUnwrap(role, context)
        return try XCTUnwrap(roles[role], context + " unknown role \(role)")
    }

    /// Changes only recorded port-name words; payload, size, and flags are untouched.
    private func remapPorts(_ bytes: Data, names: [UInt32: UInt32], offsets: [Int], context: String) throws -> Data {
        var result = [UInt8](bytes)
        for offset in offsets {
            let original = try word(in: bytes, at: offset)
            let replacement = try XCTUnwrap(names[original], context + " unmapped port word \(original)")
            for byte in 0..<4 {
                result[offset + byte] = UInt8(truncatingIfNeeded: replacement >> (8 * byte))
            }
        }
        return Data(result)
    }

    private func word(in bytes: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, bytes.count >= 4, offset <= bytes.count - 4 else {
            throw ReferenceError.invalidFixture("Port/trailer word exceeds captured bytes")
        }
        return bytes.dropFirst(offset).prefix(4).enumerated().reduce(0) {
            $0 | (UInt32($1.element) << (8 * $1.offset))
        }
    }

    private func decodeHex(_ string: String) throws -> Data {
        let characters = Array(string.utf8)
        guard characters.count.isMultiple(of: 2) else {
            throw ReferenceError.invalidFixture("Odd-length byte string")
        }
        var bytes = Data(capacity: characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            let pair = String(decoding: characters[index..<(index + 2)], as: UTF8.self)
            guard let byte = UInt8(pair, radix: 16) else {
                throw ReferenceError.invalidFixture("Invalid byte string")
            }
            bytes.append(byte)
        }
        return bytes
    }

    private func hex(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func loadReference() throws -> ReferenceEnvelope {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mach-message-reference", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReferenceEnvelope.self, from: Data(contentsOf: url))
    }

    private func assertRejected(_ expected: MachCompatibilityError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected unsupported request to throw \(expected)")
        } catch {
            XCTAssertEqual(error as? MachCompatibilityError, expected)
        }
    }
}

private enum ReferenceError: Error {
    case invalidFixture(String)
}

private struct ReferenceEnvelope: Decodable {
    let schema: Int
    let evidenceId: String
    let evidenceType: String
    let provenance: ReferenceProvenance
    let repeatability: ReferenceRepeatability
    let oracle: NativeReference
}

private struct ReferenceProvenance: Decodable {
    let source: ReferenceFile
    let headers: [ReferenceFile]
}

private struct ReferenceFile: Decodable {
    let file: String
    let sha256: String
}

private struct ReferenceRepeatability: Decodable {
    let runs: Int
    let identical: Bool
    let allChecksPassed: Bool
}

private struct NativeReference: Decodable {
    let schema: Int
    let abi: ReferenceABI
    let scenarios: [ReferenceScenario]
    let scenarioCount: Int
    let checkCount: Int
    let passed: Bool
}

private struct ReferenceABI: Decodable {
    let headerBytes: Int
    let portNameBytes: Int
    let portOffsets: [Int]
}

private struct ReferenceScenario: Decodable {
    let name: String
    let operations: [ReferenceOperation]
    let checkCount: Int
    let passed: Bool
}

private struct ReferenceOperation: Decodable {
    let sequence: Int
    let operation: String
    let role: String?
    let token: UInt32?
    let status: Int32?
    let state: ReferenceState?
    let label: String?
    let name: String?
    let passed: Bool?
    let limit: Int?
    let sendSize: Int?
    let timeoutMs: Int?
    let before: ReferenceMessage?
    let after: ReferenceMessage?
    let capacity: Int?
    let large: Bool?
    let message: ReferenceMessage?
    let normalizedStoragePrefix64Bytes: String?
    let trailer: ReferenceTrailer?
    let queueCountAfter: UInt32?
}

private struct ReferenceMessage: Decodable {
    let bits: UInt32
    let size: UInt32
    let remoteDisposition: UInt32
    let localDisposition: UInt32
    let remoteRole: String
    let localRole: String
    let voucherRole: String
    let id: Int32
    let normalizedBytes: String
}

private struct ReferenceTrailer: Decodable {
    let offset: Int
    let type: UInt32
    let size: UInt32
    let bytes: String
}

private struct ReferenceState: Decodable {
    let role: String
    let typeStatus: Int32
    let type: UInt32
    let sendRefsStatus: Int32
    let sendRefs: UInt32
    let receiveRefsStatus: Int32
    let receiveRefs: UInt32
    let deadRefsStatus: Int32
    let deadRefs: UInt32
    let queueStatus: Int32
    let queueCount: Int
    let queueLimit: Int
}
