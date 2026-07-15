import SwiftUI

struct WebDAVLocalStorageCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.arrow.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("我的 iPhone / EasySearch")
                    .font(.subheadline.weight(.semibold))
                Text("文件会保存到 App Documents，可在“文件”App 中查看。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .esCard(cornerRadius: ESUI.compactCornerRadius)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

struct WebDAVItemRow: View {
    let item: WebDAVItem
    let isTransferring: Bool
    let openAction: () -> Void
    let downloadAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                .font(.title3)
                .foregroundStyle(item.isDirectory ? Color.yellow : Color.accentColor)
                .frame(width: 28)

            Button(action: openAction) {
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
            }
            .buttonStyle(.plain)

            if isTransferring {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: downloadAction) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isDirectory ? "下载文件夹" : "下载文件")
            }
        }
        .padding(.vertical, 3)
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
