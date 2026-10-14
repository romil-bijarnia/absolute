import Foundation

public struct DesktopWindow: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case files, about }
    public let id: UUID
    public let kind: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var minimized = false

    public init(kind: Kind, x: Double = 100, y: Double = 80,
                width: Double = 1000, height: Double = 570, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DesktopSession: Codable, Equatable, Sendable {
    public private(set) var windows: [DesktopWindow] = []
    public var focusedWindow: DesktopWindow? { windows.last(where: { !$0.minimized }) }
    public init() {}

    @discardableResult
    public mutating func open(_ kind: DesktopWindow.Kind) -> UUID {
        let shift = Double(windows.count % 5) * 26
        let window = DesktopWindow(kind: kind, x: 100 + shift, y: 80 + shift,
            width: kind == .about ? 440 : 1000, height: kind == .about ? 330 : 570)
        windows.append(window)
        return window.id
    }

    public mutating func focus(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        var window = windows.remove(at: index)
        window.minimized = false
        windows.append(window)
    }

    public mutating func close(_ id: UUID) { windows.removeAll { $0.id == id } }
    public mutating func minimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].minimized = true
    }
    public mutating func move(_ id: UUID, x: Double, y: Double) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].x = x
        windows[index].y = y
    }
    public mutating func resize(_ id: UUID, width: Double, height: Double) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].width = max(620, width)
        windows[index].height = max(360, height)
    }
    public mutating func showDesktop() {
        for index in windows.indices { windows[index].minimized = true }
    }
}
