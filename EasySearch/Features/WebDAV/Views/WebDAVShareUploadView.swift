import Foundation
import SwiftUI

struct WebDAVShareUploadView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [SharedInboxItem]
    let onFinished: () -> Void
    @StateObject private var settingsStore = WebDAVSettingsStore.shared
    @State private var currentPath = ""
    @State private var folders: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var isShowingSettings = false
    @State private var errorMessage: String?

    init(items: [SharedInboxItem], onFinished: @escaping () -> Void) {
        self.items = items
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if settingsStore.configuration == nil {
                VStack(spacing: 16) {
                    ESEmptyState(
                        title: "请先配置 WebDAV",
                        message: "分享的文件已经暂存在 App Group 中，配置完成后即可继续上传。",
                        systemImage: "externaldrive.badge.questionmark"
                    )
                    Button("打开 WebDAV 设置") { isShowingSettings = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            } else {
                List {
                    if settingsStore.locations.count > 1 {
                        Section("WebDAV 位置") {
                            Picker("存储到", selection: selectedLocationBinding) {
                                ForEach(settingsStore.locations) { location in
                                    Text(location.name).tag(location.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Section("待上传") {
                        ForEach(items, id: \.id) { item in
                            Label(item.displayName, systemImage: "doc.circle")
                        }
                    }

                    Section("选择远程文件夹") {
                        if !currentPath.isEmpty {
                            Button {
                                currentPath = parentPath(of: currentPath)
                            } label: {
                                Label("返回上一级", systemImage: "chevron.left")
                            }
                        }

                        ForEach(visibleFolders) { folder in
                            Button {
                                currentPath = folder.path
                            } label: {
                                Label(folder.name, systemImage: "folder")
                            }
                        }

                        if isLoading {
                            ProgressView("读取文件夹…")
                        } else if visibleFolders.isEmpty {
                            Text("当前文件夹没有下级目录")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .disabled(isUploading)
                .overlay {
                    if isUploading { ProgressView("正在上传…") }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        upload()
                    } label: {
                        Label("存储到当前文件夹", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading || items.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
                .task(id: "\(settingsStore.configuration?.cacheKey ?? "none")-\(currentPath)") {
                    await loadFolders()
                }
            }
        }
        .navigationTitle("存储到 WebDAV")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isUploading)
        .interactiveDismissDisabled(isUploading)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
                    .disabled(isUploading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("WebDAV 设置")
                .disabled(isUploading)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                WebDAVSettingsView(store: settingsStore, showsCloseButton: true)
            }
        }
        .alert("上传失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: settingsStore.selectedLocationID) { _ in
            currentPath = ""
            folders = []
        }
    }

    private var visibleFolders: [WebDAVItem] {
        folders.filter { settingsStore.showsHiddenFolders || !$0.isHiddenFolder }
    }

    private var selectedLocationBinding: Binding<UUID> {
        Binding(
            get: {
                settingsStore.selectedLocationID
                    ?? settingsStore.locations.first?.id
                    ?? UUID()
            },
            set: { settingsStore.select(locationID: $0) }
        )
    }

    private func loadFolders() async {
        guard let configuration = settingsStore.configuration else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            folders = try await WebDAVClient(configuration: configuration)
                .list(path: currentPath)
                .filter(\.isDirectory)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upload() {
        guard let configuration = settingsStore.configuration else { return }
        let destinationPath = currentPath
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let client = WebDAVClient(configuration: configuration)
                for item in items {
                    guard FileManager.default.fileExists(atPath: item.localURL.path) else {
                        throw WebDAVError.localFileMissing
                    }
                    try await client.upload(
                        localURL: item.localURL,
                        remotePath: join(destinationPath, item.displayName)
                    )
                }
                onFinished()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parentPath(of path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        lhs.isEmpty ? rhs : "\(lhs)/\(rhs)"
    }
}
