import Foundation
import CoreGraphics
import Metal
import IOSurface

// Owned, headless workload. No windows, display capture, event injection,
// display mode changes, private APIs, or hardware identifiers are requested.
enum ProbeError: Error {
    case unavailable(String)
}

var results: [String: Any] = ["evidenceType": "owned-process-runtime-observation"]

func check(_ name: String, _ body: () throws -> [String: Any]) {
    do {
        var value = try body()
        value["status"] = "passed"
        results[name] = value
    } catch {
        results[name] = ["status": "failed", "error": String(describing: error)]
    }
}

check("coreGraphicsBitmap") {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: 8, height: 8,
                                  bitsPerComponent: 8, bytesPerRow: 32,
                                  space: colorSpace,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                      CGImageAlphaInfo.premultipliedLast.rawValue),
          let memory = context.data else {
        throw ProbeError.unavailable("RGBA bitmap context")
    }
    context.setFillColorSpace(colorSpace)
    context.setFillColor([1, 0, 0, 1])
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let bytes = memory.assumingMemoryBound(to: UInt8.self)
    let exact = (0..<64).allSatisfy { pixel in
        let i = pixel * 4
        return Array(UnsafeBufferPointer(start: bytes + i, count: 4)) == [255, 0, 0, 255]
    }
    guard exact else {
        let sample = Array(UnsafeBufferPointer(start: bytes, count: 4))
        throw ProbeError.unavailable("bitmap bytes differ from expected device-RGB red: \(sample)")
    }
    return ["width": 8, "height": 8, "format": "RGBA8 premultiplied-last big-endian",
            "allPixelsMatch": exact]
}

check("ioSurfaceSharedMemory") {
    let properties: [IOSurfacePropertyKey: Any] = [
        .width: 8, .height: 8, .bytesPerElement: 4, .bytesPerRow: 32,
        .allocSize: 256, .pixelFormat: UInt32(0x42475241),
    ]
    guard let surface = IOSurface(properties: properties) else {
        throw ProbeError.unavailable("IOSurface creation")
    }
    var writeLockSeed: UInt32 = 0
    var writeUnlockSeed: UInt32 = 0
    var readLockSeed: UInt32 = 0
    var readUnlockSeed: UInt32 = 0
    guard surface.lock(options: [], seed: &writeLockSeed) == kIOReturnSuccess else {
        throw ProbeError.unavailable("IOSurface lock")
    }
    let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
    bytes[0] = 17
    bytes[1] = 34
    bytes[2] = 51
    bytes[3] = 255
    let width = surface.width
    let height = surface.height
    let stride = surface.bytesPerRow
    guard surface.unlock(options: [], seed: &writeUnlockSeed) == kIOReturnSuccess else {
        throw ProbeError.unavailable("IOSurface unlock")
    }
    guard surface.lock(options: .readOnly, seed: &readLockSeed) == kIOReturnSuccess else {
        throw ProbeError.unavailable("IOSurface read lock")
    }
    let match = Array(UnsafeBufferPointer(start: bytes, count: 4)) == [17, 34, 51, 255]
    guard surface.unlock(options: .readOnly, seed: &readUnlockSeed) == kIOReturnSuccess else {
        throw ProbeError.unavailable("IOSurface read unlock")
    }
    guard match else { throw ProbeError.unavailable("IOSurface round-trip differs") }
    guard width == 8, height == 8, stride == 32, surface.planeCount == 0,
          surface.bytesPerElement == 4, surface.allocationSize >= 256,
          surface.pixelFormat == UInt32(0x42475241) else {
        throw ProbeError.unavailable("IOSurface layout differs from requested nonplanar BGRA")
    }
    return ["width": width, "height": height, "bytesPerRow": stride,
            "planeCount": surface.planeCount, "allocationBytes": surface.allocationSize,
            "bytesPerElement": surface.bytesPerElement, "firstPixelRoundTrip": match,
            "writeLockSeed": writeLockSeed, "writeUnlockSeed": writeUnlockSeed,
            "readLockSeed": readLockSeed, "readUnlockSeed": readUnlockSeed]
}

check("metalBufferTransfer") {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let source = device.makeBuffer(length: 4096, options: .storageModeShared),
          let destination = device.makeBuffer(length: 4096, options: .storageModeShared),
          let command = queue.makeCommandBuffer(),
          let encoder = command.makeBlitCommandEncoder() else {
        throw ProbeError.unavailable("Metal device/queue/buffers/encoder")
    }
    let sourceBytes = source.contents().assumingMemoryBound(to: UInt8.self)
    let destinationBytes = destination.contents().assumingMemoryBound(to: UInt8.self)
    for i in 0..<4096 {
        sourceBytes[i] = UInt8(truncatingIfNeeded: i &* 13 &+ 7)
        destinationBytes[i] = 0
    }
    encoder.copy(from: source, sourceOffset: 0, to: destination,
                 destinationOffset: 0, size: 4096)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
        throw command.error ?? ProbeError.unavailable("Metal command did not complete")
    }
    let match = (0..<4096).allSatisfy { sourceBytes[$0] == destinationBytes[$0] }
    guard match else { throw ProbeError.unavailable("Metal transfer bytes differ") }
    return ["deviceName": device.name, "hasUnifiedMemory": device.hasUnifiedMemory,
            "supportsApple9": device.supportsFamily(.apple9),
            "supportsRaytracing": device.supportsRaytracing,
            "bytesCompared": 4096, "allBytesMatch": match,
            "commandStatus": "completed"]
}

check("metalOffscreenRender") {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let command = queue.makeCommandBuffer() else {
        throw ProbeError.unavailable("Metal device/queue/command")
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = .renderTarget
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw ProbeError.unavailable("Metal offscreen texture")
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0.5, blue: 0.25, alpha: 1)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
        throw ProbeError.unavailable("Metal render encoder")
    }
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
        throw command.error ?? ProbeError.unavailable("offscreen render did not complete")
    }
    var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
    pixels.withUnsafeMutableBytes { bytes in
        texture.getBytes(bytes.baseAddress!, bytesPerRow: 64,
                         from: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0)
    }
    let match = (0..<256).allSatisfy { pixel in
        let i = pixel * 4
        return abs(Int(pixels[i]) - 64) <= 1 && abs(Int(pixels[i + 1]) - 128) <= 1 &&
            pixels[i + 2] == 255 && pixels[i + 3] == 255
    }
    guard match else { throw ProbeError.unavailable("offscreen BGRA pixels differ") }
    return ["width": 16, "height": 16, "format": "BGRA8Unorm",
            "allPixelsMatchWithinOneUnormStep": match,
            "firstPixel": Array(pixels.prefix(4)), "commandStatus": "completed"]
}

check("metalComputeShader") {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let buffer = device.makeBuffer(length: 1024 * MemoryLayout<UInt32>.stride,
                                         options: .storageModeShared),
          let command = queue.makeCommandBuffer(),
          let encoder = command.makeComputeCommandEncoder() else {
        throw ProbeError.unavailable("Metal compute resources")
    }
    let shader = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void absolute_probe(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) {
        values[i] = i * 17u + 3u;
    }
    """
    let library = try device.makeLibrary(source: shader, options: nil)
    guard let function = library.makeFunction(name: "absolute_probe") else {
        throw ProbeError.unavailable("compiled compute function")
    }
    let pipeline = try device.makeComputePipelineState(function: function)
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    encoder.dispatchThreads(MTLSize(width: 1024, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth,
                                                          height: 1, depth: 1))
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
        throw command.error ?? ProbeError.unavailable("compute command did not complete")
    }
    let values = buffer.contents().assumingMemoryBound(to: UInt32.self)
    let match = (0..<1024).allSatisfy { values[$0] == UInt32($0 * 17 + 3) }
    guard match else { throw ProbeError.unavailable("compute results differ from CPU reference") }
    return ["valuesCompared": 1024, "allValuesMatch": match,
            "threadExecutionWidth": pipeline.threadExecutionWidth,
            "commandStatus": "completed"]
}

let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data([10]))
if results.values.compactMap({ $0 as? [String: Any] }).contains(where: { $0["status"] as? String == "failed" }) {
    exit(1)
}
