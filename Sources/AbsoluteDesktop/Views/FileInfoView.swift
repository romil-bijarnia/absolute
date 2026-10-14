import SwiftUI
import AbsoluteCore

struct FileInfoView: View {
    let entry: FileEntry
    let fileService: any FileService
    let host: MacHost
    let reveal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var information: FileInformation?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: host.icon(for: entry.url)).resizable().scaledToFit().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.title2).fontWeight(.semibold).lineLimit(2)
                    Text("Information").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if let information {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 13) {
                    detail("Kind", information.entry.isSymbolicLink ? "Symbolic link" : information.entry.kind.rawValue.capitalized)
                    detail("Size", information.entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable")
                    detail("Location", information.entry.url.deletingLastPathComponent().path)
                    detail("Created", dateLabel(information.createdAt))
                    detail("Modified", dateLabel(information.entry.modifiedAt))
                    if let permissions = information.posixPermissions {
                        detail("Permissions", String(format: "%04o", permissions & 0o7777))
                    }
                    if let link = information.symbolicLinkDestination { detail("Link target", link) }
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else { ProgressView("Reading information…") }
            Spacer(minLength: 4)
            HStack {
                Button { reveal(); dismiss() } label: {
                    Text("Show Containing Folder").padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                }
                    .disabled(information == nil)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done").padding(.horizontal, 16).padding(.vertical, 7)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                }.keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.plain)
        }
        .padding(26).frame(width: 500, height: 410)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: entry.id) {
            let url = entry.url
            let service = fileService
            let result = await Task.detached(priority: .userInitiated) {
                Result { try service.information(for: url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let value): information = value
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 12))
    }
    private func dateLabel(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable"
    }
}
