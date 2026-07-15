import SwiftUI
import UniformTypeIdentifiers

struct WebDAVView: View {
    @StateObject private var settingsStore = WebDAVSettingsStore.shared
    @State private var currentPath = ""
    @State private var items: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var isShowingSettings = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var activeTransferPath: String?

    var body: some View {
        Group {
            if settingsStore.configuration == nil {
                configurationPrompt
            } else {
                browserContent
            }
        }
        .navigationTitle(currentPath.isEmpty ? "WebDAV 文件" : currentPath.split(separator: "/").last.map(String.init) ?? "WebDAV 文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                WebDAVSettingsView(store: settingsStore)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult
        )
        .alert("WebDAV", isPresented: alertBinding) {
            Button("好", role: .cancel) { errorMessage = nil; statusMessage = nil }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
        .task(id: "\(settingsStore.configuration?.cacheKey ?? "not-configured")|\(currentPath)") {
            guard settingsStore.configuration != nil else { return }
            await reload()
        }
    }

    private var configurationPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ESInfoBanner(
                    title: "还没有连接 WebDAV",
                    message: "配置服务器地址、用户名和密码后，就可以在这里浏览、上传和下载文件。",
                    systemImage: "externaldrive.badge.questionmark",
                    tone: .accent
                )

                Button {
                    isShowingSettings = true
                } label: {
                    Label("配置 WebDAV 连接", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                WebDAVLocalStorageCard()
            }
            .padding(ESUI.screenHorizontalPadding)
            .padding(.top, 18)
        }
        .esScreenBackground()
    }

    private var browserContent: some View {
        List {
            if !currentPath.isEmpty {
                Button {
                    currentPath = parentPath(of: currentPath)
                } label: {
                    Label("返回上一级", systemImage: "chevron.left")
                }
            }

            if isLoading && items.isEmpty {
                HStack {
                    ProgressView()
                    Text("正在读取目录…")
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                ESEmptyState(
                    title: "目录为空",
                    message: "可以使用右上角按钮上传文件。",
                    systemImage: "folder",
                    minHeight: 180
                )
            } else {
                ForEach(items) { item in
                    WebDAVItemRow(
                        item: item,
                        isTransferring: activeTransferPath == item.path,
                        openAction: { open(item) },
                        downloadAction: { download(item) }
                    )
                }
            }

            Section {
                WebDAVLocalStorageCard()
            } header: {
                Text("本地下载位置")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await reload()
        }
        .overlay {
            if isLoading && !items.isEmpty {
                ProgressView()
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .esScreenBackground()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if settingsStore.configuration != nil {
            ToolbarItem(placement: .topBarLeading) {
                if !currentPath.isEmpty {
                    Button {
                        currentPath = parentPath(of: currentPath)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回上一级")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "arrow.up.doc")
                }
                .accessibilityLabel("上传文件")
                .disabled(isLoading)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("WebDAV 设置")

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新目录")
                .disabled(isLoading)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("配置 WebDAV")
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || statusMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                    statusMessage = nil
                }
            }
        )
    }

    private func reload() async {
        guard let configuration = settingsStore.configuration else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await WebDAVClient(configuration: configuration).list(path: currentPath)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ item: WebDAVItem) {
        guard item.isDirectory else {
            download(item)
            return
        }
        currentPath = item.path
    }

    private func download(_ item: WebDAVItem) {
        guard let configuration = settingsStore.configuration else { return }
        activeTransferPath = item.path
        Task {
            defer { activeTransferPath = nil }
            do {
                let localURL = try await WebDAVClient(configuration: configuration).download(
                    item: item,
                    into: WebDAVLocalFileStore.rootURL
                )
                statusMessage = "已保存到 我的 iPhone/EasySearch/\(relativeLocalPath(localURL))"
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let configuration = settingsStore.configuration else { return }
        let destinationPath = currentPath
        switch result {
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        case let .success(urls):
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    for url in urls {
                        let stagedUpload = try WebDAVLocalFileStore.stageForUpload(url)
                        do {
                            try await WebDAVClient(configuration: configuration).upload(
                                localURL: stagedUpload.localURL,
                                remotePath: join(destinationPath, stagedUpload.remoteFileName)
                            )
                            WebDAVLocalFileStore.removeStagedUpload(stagedUpload)
                        } catch {
                            WebDAVLocalFileStore.removeStagedUpload(stagedUpload)
                            throw error
                        }
                    }
                    statusMessage = "上传完成"
                    if currentPath == destinationPath {
                        items = try await WebDAVClient(configuration: configuration).list(path: destinationPath)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = error.localizedDescription
                }
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

    private func relativeLocalPath(_ url: URL) -> String {
        let root = WebDAVLocalFileStore.rootURL.path
        return url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count + 1)) : url.lastPathComponent
    }
}

#Preview {
    NavigationStack { WebDAVView() }
}
