import SwiftUI
import AbsoluteCore

struct DesktopWindowView<Content: View>: View {
    @Bindable var desktop: DesktopStore
    let window: DesktopWindow
    let bounds: CGSize
    @ViewBuilder var content: () -> Content
    @GestureState private var drag = CGSize.zero
    @GestureState private var resize = CGSize.zero
    @State private var savedFrame: DesktopWindow?

    private var width: Double { min(max(window.kind == .about ? 440 : 620, window.width + resize.width), bounds.width - 32) }
    private var height: Double { min(max(window.kind == .about ? 330 : 360, window.height + resize.height), bounds.height - 145) }
    private var originX: Double { min(max(16, window.x + drag.width), max(16, bounds.width - width - 16)) }
    private var originY: Double { min(max(45, window.y + drag.height), max(45, bounds.height - height - 105)) }
    private var title: String {
        window.kind == .about ? "About Absolute" : desktop.browsers[window.id]?.title ?? "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Divider().opacity(0.6)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        .overlay(alignment: .bottomTrailing) {
            if window.kind == .files {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1)
                        .updating($resize) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            desktop.session.resize(window.id,
                                width: min(window.width + value.translation.width, bounds.width - originX - 16),
                                height: min(window.height + value.translation.height, bounds.height - originY - 105))
                        })
                    .accessibilityLabel("Resize \(title) window")
            }
        }
        .shadow(color: .black.opacity(desktop.session.focusedWindow?.id == window.id ? 0.35 : 0.18), radius: 25, y: 12)
        .position(x: originX + width / 2, y: originY + height / 2)
        .simultaneousGesture(TapGesture().onEnded { desktop.focus(window.id) })
    }

    private var titlebar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                control("Close \(title) window", color: .red) { desktop.close(window.id) }
                control("Minimize \(title) window", color: .yellow) { desktop.session.minimize(window.id) }
                control("Maximize \(title) window", color: .green) { maximize() }
            }.padding(.leading, 17).frame(width: 96, alignment: .leading)
            Spacer()
            Image(systemName: window.kind == .about ? "circle.hexagongrid.fill" : "folder.fill")
                .font(.system(size: 12)).foregroundStyle(window.kind == .about ? Color.cyan : Color.blue)
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 6)
            Spacer()
            Color.clear.frame(width: 96, height: 1)
        }
        .frame(height: 43)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                desktop.focus(window.id)
                desktop.session.move(window.id,
                    x: min(max(16, window.x + value.translation.width), max(16, bounds.width - width - 16)),
                    y: min(max(45, window.y + value.translation.height), max(45, bounds.height - height - 105)))
            })
        .onTapGesture(count: 2) { maximize() }
    }

    private func control(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Circle().fill(color.gradient).frame(width: 12, height: 12) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func maximize() {
        guard window.kind == .files else { return }
        if let frame = savedFrame {
            desktop.session.resize(window.id, width: frame.width, height: frame.height)
            desktop.session.move(window.id, x: frame.x, y: frame.y)
            savedFrame = nil
        } else {
            savedFrame = window
            desktop.session.resize(window.id, width: bounds.width - 32, height: bounds.height - 150)
            desktop.session.move(window.id, x: 16, y: 45)
        }
    }
}
