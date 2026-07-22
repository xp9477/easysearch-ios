import Foundation
import SwiftUI

struct WebDAVItemDetailsRequest: Identifiable {
    let id = UUID()
    let configuration: WebDAVConfiguration
    let item: WebDAVItem
}

struct WebDAVItemDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let request: WebDAVItemDetailsRequest
    @State private var details: WebDAVItemDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: request.item.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.title2)
                        .foregroundStyle(request.item.isDirectory ? Color.yellow : Color.accentColor)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.item.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(request.configuration.displayName.isEmpty
                             ? (request.configuration.baseURL.host ?? "WebDAV")
                             : request.configuration.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("详情") {
                detailRow(title: "类型", value: request.item.isDirectory ? "文件夹" : fileTypeText)
                detailRow(title: "路径", value: request.item.path)
                if let modifiedAt = request.item.modifiedAt {
                    detailRow(
                        title: "修改时间",
                        value: modifiedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if !request.item.isDirectory, let contentLength = request.item.contentLength {
                    detailRow(
                        title: "大小",
                        value: ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file)
                    )
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text(request.item.isDirectory ? "正在统计文件夹内容…" : "正在读取详情…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let details {
                Section("内容") {
                    detailRow(title: "文件数量", value: "\(details.fileCount)")
                    if request.item.isDirectory {
                        detailRow(title: "子文件夹数量", value: "\(details.folderCount)")
                    }
                    detailRow(title: "总大小", value: totalSizeText(details))
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await loadDetails() }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("项目详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .task { await loadDetails() }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var fileTypeText: String {
        if let contentType = request.item.contentType, !contentType.isEmpty {
            return contentType
        }
        let ext = (request.item.name as NSString).pathExtension
        return ext.isEmpty ? "文件" : "\(ext.uppercased()) 文件"
    }

    private func totalSizeText(_ details: WebDAVItemDetails) -> String {
        let size = ByteCountFormatter.string(fromByteCount: details.totalSize, countStyle: .file)
        guard details.unknownSizeFileCount > 0 else { return size }
        if details.totalSize == 0 {
            return "未知（\(details.unknownSizeFileCount) 个文件未报告大小）"
        }
        return "至少 \(size)（\(details.unknownSizeFileCount) 个文件未报告大小）"
    }

    private func loadDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            details = try await WebDAVClient(configuration: request.configuration)
                .details(for: request.item)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
