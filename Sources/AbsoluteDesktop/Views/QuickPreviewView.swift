import SwiftUI
import AbsoluteCore

struct QuickPreviewView: View {
    let entry: FileEntry
    let host: MacHost
    @Environment(\.dismiss) private var dismiss
    @State private var preview: TextPreview?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: host.icon(for: entry.url)).resizable().frame(width: 22, height: 22)
                Text(entry.name).font(.headline).lineLimit(1)
                Spacer()
                Button("Open") { _ = host.open(entry.url) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            Group {
                if entry.kind == .image, (entry.size ?? 0) < 25 * 1024 * 1024,
                   let image = NSImage(contentsOf: entry.url) {
                    Image(nsImage: image).resizable().scaledToFit().padding(24)
                } else if let error {
                    ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text(error))
                } else if case .text(let text, let truncated) = preview {
                    VStack(spacing: 0) {
                        ScrollView([.vertical, .horizontal]) {
                            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading).padding(20)
                        }
                        if truncated { Text("Showing the first 128 KB").font(.caption).foregroundStyle(.secondary).padding(8) }
                    }
                } else if preview == .unsupported {
                    ContentUnavailableView("Open this file in its application", systemImage: "doc",
                        description: Text("Text and image previews are available here."))
                } else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 470)
        .task(id: entry.id) {
            let url = entry.url
            let result = await Task.detached {
                Result { try TextPreviewReader().read(url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let content): preview = content
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
