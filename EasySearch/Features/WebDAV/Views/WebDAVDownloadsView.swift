import Foundation
import SwiftUI

struct WebDAVDownloadsView: View {
    @ObservedObject var manager: WebDAVDownloadManager
    @State private var localItems: [WebDAVLocalDownloadItem] = []

    init(manager: WebDAVDownloadManager = .shared) {
        self.manager = manager
    }

    var body: some View {
        Group {
            if manager.jobs.isEmpty && localItems.isEmpty {
                ESEmptyState(
                    title: "暂无下载",
                    message: "长按 WebDAV 中的文件或文件夹即可加入下载。",
                    systemImage: "arrow.down.circle"
                )
                .padding(20)
            } else {
                List {
                    if !manager.jobs.isEmpty {
                        Section("任务") {
                            ForEach(Array(manager.jobs.reversed())) { job in
                                WebDAVDownloadJobRow(job: job, manager: manager)
                            }
                        }
                    }

                    if !localItems.isEmpty {
                        Section("已下载内容") {
                            ForEach(localItems) { item in
                                WebDAVLocalDownloadRow(item: item)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { loadLocalItems() }
            }
        }
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if manager.jobs.contains(where: { !$0.state.isActive }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.clearFinished()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清除已结束任务")
                }
            }
        }
        .esScreenBackground()
        .task { loadLocalItems() }
        .onChange(of: completedURLs) { _ in
            loadLocalItems()
        }
    }

    private var completedURLs: [URL] {
        manager.jobs.compactMap { job in
            if case let .completed(url) = job.state { return url }
            return nil
        }
    }

    private func loadLocalItems() {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: WebDAVLocalFileStore.rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        localItems = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return WebDAVLocalDownloadItem(
                url: url,
                isDirectory: values.isDirectory == true,
                fileSize: values.fileSize.map { Int64($0) },
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}

private struct WebDAVLocalDownloadItem: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?

    var id: URL { url }
}

private struct WebDAVLocalDownloadRow: View {
    let item: WebDAVLocalDownloadItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.isDirectory ? Color.yellow : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("共享\(item.url.lastPathComponent)")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        var values: [String] = [item.isDirectory ? "文件夹" : "文件"]
        if let fileSize = item.fileSize, !item.isDirectory {
            values.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        if let modifiedAt = item.modifiedAt {
            values.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return values.joined(separator: " · ")
    }
}

private struct WebDAVDownloadJobRow: View {
    let job: WebDAVDownloadJob
    @ObservedObject var manager: WebDAVDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: job.item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(job.item.isDirectory ? Color.yellow : Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(job.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                trailingControl
            }

            if job.state.isActive {
                progressView
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch job.state {
        case .queued, .preparing, .downloading:
            Button {
                manager.cancel(jobID: job.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("取消下载")
        case .cancelling:
            ProgressView()
                .controlSize(.small)
        case .failed, .cancelled:
            Button {
                manager.retry(jobID: job.id)
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("重试下载")
        case let .completed(url):
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("共享已下载文件")
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if let fraction = job.progress?.fractionCompleted {
            ProgressView(value: fraction)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        switch job.state {
        case .queued, .preparing, .downloading:
            Button(role: .destructive) {
                manager.cancel(jobID: job.id)
            } label: {
                Label("取消下载", systemImage: "xmark.circle")
            }
        case .cancelling:
            EmptyView()
        case .failed, .cancelled:
            Button {
                manager.retry(jobID: job.id)
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                manager.remove(jobID: job.id)
            } label: {
                Label("移除记录", systemImage: "trash")
            }
        case let .completed(url):
            ShareLink(item: url) {
                Label("共享", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                manager.remove(jobID: job.id)
            } label: {
                Label("移除记录", systemImage: "trash")
            }
        }
    }

    private var statusText: String {
        switch job.state {
        case .queued:
            return "等待下载"
        case .preparing:
            return "正在统计内容…"
        case .downloading:
            guard let progress = job.progress else { return "正在下载…" }
            let fileProgress = progress.totalFiles > 0
                ? "\(progress.completedFiles)/\(progress.totalFiles) 个文件"
                : "正在创建文件夹"
            if let totalBytes = progress.totalBytes, totalBytes > 0 {
                return "\(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) · \(fileProgress)"
            }
            return "\(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)) · \(fileProgress)"
        case .cancelling:
            return "正在取消…"
        case .completed:
            return "下载完成"
        case let .failed(message):
            return message
        case .cancelled:
            return "已取消"
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .failed:
            return .red
        case .completed:
            return .green
        case .queued, .preparing, .downloading, .cancelling, .cancelled:
            return .secondary
        }
    }
}
