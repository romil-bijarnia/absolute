import Foundation

public struct NavigationHistory: Sendable {
    public private(set) var current: URL
    public private(set) var backStack: [URL] = []
    public private(set) var forwardStack: [URL] = []

    public init(initial: URL) { current = initial.standardizedFileURL }
    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public mutating func navigate(to url: URL) {
        let next = url.standardizedFileURL
        guard next != current else { return }
        backStack.append(current)
        current = next
        forwardStack.removeAll()
    }

    public mutating func goBack() {
        guard let next = backStack.popLast() else { return }
        forwardStack.append(current)
        current = next
    }

    public mutating func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }
}
