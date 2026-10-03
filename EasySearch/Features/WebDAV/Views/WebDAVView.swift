import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WebDAVView: View {
    @StateObject private var settingsStore = WebDAVSettingsStore.shared
    @StateObject private var downloadManager = WebDAVDownloadManager.shared
    @State private var currentPath = ""
    @State private var items: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var isShowingSettings = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var previewRequest: WebDAVPreviewRequest?
    @State private var detailsRequest: WebDAVItemDetailsRequest?
    @State private var deletionRequest: WebDAVDeletionRequest?
    @State private var renamingItem: WebDAVItem?
    @State private var renameText = ""
    @State private var movingItem: WebDAVItem?

    private var visibleItems: [WebDAVItem] {
        items.filter { settingsStore.showsHiddenFolders || !$0.isHiddenFolder }
    }

    var body: some View {
        Group {
            if settingsStore.configuration == nil {
                configurationPrompt
            } else {
                browserContent
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                WebDAVSettingsView(store: settingsStore, showsCloseButton: true)
            }
        }
        .sheet(item: $previewRequest) { request in
            NavigationStack {
                WebDAVPreviewView(request: request)
            }
        }
        .sheet(item: $detailsRequest) { request in
            NavigationStack {
                WebDAVItemDetailsView(request: request)
            }
        }
        .sheet(item: $movingItem) { item in
            if let configuration = settingsStore.configuration {
                NavigationStack {
                    WebDAVMovePickerView(
                        configuration: configuration,
                        movingItem: item,
                        initialDirectory: currentPath
                    ) { targetDirectory in
                        performMove(item: item, toDirectory: targetDirectory)
                    }
                }
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renamingItem != nil },
            set: { if !$0 { renamingItem = nil } }
        )) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let item = renamingItem {
                    performRename(item: item, newName: renameText)
                }
                renamingItem = nil
            }
            Button("取消", role: .cancel) { renamingItem = nil }
        } message: {
            Text("请输入新的文件或文件夹名称。")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult
        )
        .alert("WebDAV", isPresented: messageAlertBinding) {
            Button("好", role: .cancel) {
                errorMessage = nil
                statusMessage = nil
            }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
        .alert("确认删除？", isPresented: deletionAlertBinding, presenting: deletionRequest) { request in
            Button("删除", role: .destructive) {
                delete(request)
            }
            Button("取消", role: .cancel) { deletionRequest = nil }
        } message: { request in
            Text(request.item.isDirectory
                 ? "将永久删除文件夹“\(request.item.name)”及其中全部内容，此操作无法撤销。"
                 : "将永久删除文件“\(request.item.name)”，此操作无法撤销。")
        }
        .task(id: "\(settingsStore.configuration?.cacheKey ?? "not-configured")|\(currentPath)") {
            guard settingsStore.configuration != nil else { return }
            try? await ExternalStorageFilesCoordinator.shared.sync(locations: settingsStore.locations)
            await reload()
        }
        .onChange(of: settingsStore.selectedLocationID) { _ in
            currentPath = ""
            items = []
        }
    }

    private var navigationTitle: String {
        if !currentPath.isEmpty {
            return currentPath.split(separator: "/").last.map(String.init) ?? "外置存储"
        }
        return settingsStore.selectedLocation?.name ?? "外置存储"
    }

    private var configurationPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "外置存储",
                    subtitle: "浏览 · 上传 · 下载远程文件",
                    featureID: "webdav",
                    systemImage: "externaldrive.fill"
                )

                ESInfoBanner(
                    title: "还没有连接外置存储",
                    message: "添加一个或多个外置存储（WebDAV / SMB）位置后，就可以浏览、上传和管理文件。",
                    systemImage: "externaldrive.badge.questionmark",
                    tone: .accent
                )

                ESPrimaryCTA(title: "添加存储位置", systemImage: "plus.circle") {
                    isShowingSettings = true
                }
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
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
            } else if visibleItems.isEmpty {
                ESEmptyState(
                    title: "目录为空",
                    message: "可以使用右上角按钮上传文件。",
                    systemImage: "folder",
                    minHeight: 180
                )
            } else {
                ForEach(visibleItems) { item in
                    WebDAVItemRow(item: item) {
                        open(item)
                    }
                    .contextMenu {
                        Button {
                            enqueueDownload(item)
                        } label: {
                            Label(item.isDirectory ? "下载文件夹" : "下载文件", systemImage: "arrow.down.circle")
                        }

                        Button {
                            showDetails(item)
                        } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }

                        Button {
                            startRenaming(item)
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }

                        Button {
                            startMoving(item)
                        } label: {
                            Label("移动到…", systemImage: "folder")
                        }

                        Divider()

                        Button(role: .destructive) {
                            prepareDeletion(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
        .overlay {
            if isLoading && !items.isEmpty {
                ProgressView()
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

                NavigationLink {
                    WebDAVDownloadsView(manager: downloadManager)
                } label: {
                    Image(systemName: downloadManager.activeCount > 0
                          ? "tray.full.fill"
                          : "tray.full")
                }
                .accessibilityLabel(downloadManager.activeCount > 0
                                    ? "下载任务，\(downloadManager.activeCount) 项进行中"
                                    : "下载任务")

                Menu {
                    if settingsStore.locations.count > 1 {
                        Menu("切换位置") {
                            ForEach(settingsStore.locations) { location in
                                Button {
                                    settingsStore.select(locationID: location.id)
                                } label: {
                                    if settingsStore.selectedLocationID == location.id {
                                        Label(location.name, systemImage: "checkmark")
                                    } else {
                                        Text(location.name)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("外置存储设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    WebDAVDownloadsView(manager: downloadManager)
                } label: {
                    Image(systemName: downloadManager.activeCount > 0 ? "tray.full.fill" : "tray.full")
                }
                .accessibilityLabel("下载任务")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("添加存储位置")
            }
        }
    }

    private var messageAlertBinding: Binding<Bool> {
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

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { deletionRequest != nil },
            set: { if !$0 { deletionRequest = nil } }
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

    private func startRenaming(_ item: WebDAVItem) {
        renamingItem = item
        renameText = item.name
    }

    private func performRename(item: WebDAVItem, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else {
            errorMessage = "名称不能包含斜杠或反斜杠"
            return
        }
        guard let configuration = settingsStore.configuration else { return }
        let parent = parentPath(of: item.path)
        let destination = join(parent, trimmed)
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await WebDAVClient(configuration: configuration).move(item: item, to: destination)
                if let locID = settingsStore.selectedLocationID {
                    Task { try? await ExternalStorageFilesCoordinator.shared.notifyChanges(locationID: locID, path: destination) }
                }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startMoving(_ item: WebDAVItem) {
        movingItem = item
    }

    private func performMove(item: WebDAVItem, toDirectory: String) {
        guard let configuration = settingsStore.configuration else { return }
        let destination = join(toDirectory, item.name)
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await WebDAVClient(configuration: configuration).move(item: item, to: destination)
                if let locID = settingsStore.selectedLocationID {
                    Task { try? await ExternalStorageFilesCoordinator.shared.notifyChanges(locationID: locID, path: destination) }
                }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ item: WebDAVItem) {
        guard let configuration = settingsStore.configuration else { return }
        if item.isDirectory {
            currentPath = item.path
        } else {
            previewRequest = WebDAVPreviewRequest(configuration: configuration, item: item)
        }
    }

    private func enqueueDownload(_ item: WebDAVItem) {
        guard let configuration = settingsStore.configuration else { return }
        downloadManager.enqueue(configuration: configuration, item: item)
    }

    private func showDetails(_ item: WebDAVItem) {
        guard let configuration = settingsStore.configuration else { return }
        detailsRequest = WebDAVItemDetailsRequest(configuration: configuration, item: item)
    }

    private func prepareDeletion(_ item: WebDAVItem) {
        guard let configuration = settingsStore.configuration else { return }
        deletionRequest = WebDAVDeletionRequest(configuration: configuration, item: item)
    }

    private func delete(_ request: WebDAVDeletionRequest) {
        deletionRequest = nil
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await WebDAVClient(configuration: request.configuration).delete(item: request.item)
                if let locID = settingsStore.selectedLocationID {
                    Task { try? await ExternalStorageFilesCoordinator.shared.notifyChanges(locationID: locID, path: request.item.path) }
                }
                if settingsStore.configuration?.cacheKey == request.configuration.cacheKey {
                    items.removeAll(where: { $0.id == request.item.id })
                }
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
                    if let locID = settingsStore.selectedLocationID {
                        Task { try? await ExternalStorageFilesCoordinator.shared.notifyChanges(locationID: locID, path: destinationPath) }
                    }
                    if currentPath == destinationPath,
                       settingsStore.configuration?.cacheKey == configuration.cacheKey {
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
}

private struct WebDAVDeletionRequest: Identifiable {
    let id = UUID()
    let configuration: WebDAVConfiguration
    let item: WebDAVItem
}

#Preview {
    NavigationStack { WebDAVView() }
}
