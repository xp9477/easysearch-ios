import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WebDAVItemRow: View {
    let item: WebDAVItem
    let openAction: () -> Void

    var body: some View {
        Button(action: openAction) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(item.isDirectory ? Color.yellow : Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.isDirectory ? "打开文件夹" : "预览文件")
    }

    private var iconName: String {
        guard !item.isDirectory else { return "folder.fill" }
        let fileExtension = (item.name as NSString).pathExtension.lowercased()
        if ["zip", "rar", "7z", "tar", "gz", "bz2"].contains(fileExtension) {
            return "archivebox"
        }
        guard let type = UTType(filenameExtension: fileExtension) else {
            return "doc"
        }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return "play.rectangle" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    private var detailText: String {
        var values: [String] = []
        if let contentLength = item.contentLength, !item.isDirectory {
            values.append(ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file))
        }
        if let modifiedAt = item.modifiedAt {
            values.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return values.isEmpty ? (item.isDirectory ? "文件夹" : "文件") : values.joined(separator: " · ")
    }
}
