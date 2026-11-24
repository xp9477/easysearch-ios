import Foundation
import SwiftUI

struct WebDAVSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WebDAVSettingsStore
    @ObservedObject private var filesCoordinator = ExternalStorageFilesCoordinator.shared
    let showsCloseButton: Bool

    @State private var editorDestination: LocationEditorDestination?
    @State private var pendingDeletion: WebDAVLocation?
    @State private var isSyncingFiles = false
    @State private var isShowingLicenseSheet = false

    init(store: WebDAVSettingsStore = .shared, showsCloseButton: Bool = false) {
        self.store = store
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        List {
            Section("存储位置") {
                ForEach(store.locations) { location in
                    locationRow(location)
                }

                Button {
                    editorDestination = LocationEditorDestination(locationID: UUID(), isNew: true)
                } label: {
                    Label("添加存储位置", systemImage: "plus")
                }
            }

            Section("偏好设置") {
                Button(action: syncToFiles) {
                    if isSyncingFiles {
                        ProgressView("正在同步到系统「文件」…")
                    } else {
                        Label("同步到系统「文件」", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncingFiles)

                if let error = filesCoordinator.lastError {
                    Label("同步失败：\(error)", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                } else if filesCoordinator.statusMessage != nil {
                    Text("已同步 \(filesCoordinator.syncedDomainCount) 个位置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle("显示隐藏文件夹", isOn: Binding(
                    get: { store.showsHiddenFolders },
                    set: { store.setShowsHiddenFolders($0) }
                ))
            }

            Section {
                DisclosureGroup("当前位置说明") {
                    Text("当前位置用于文件浏览和从分享菜单上传；可在文件管理页切换。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isShowingLicenseSheet = true
                } label: {
                    HStack {
                        Label("开源许可", systemImage: "doc.text")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("外置存储设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $editorDestination) { destination in
            NavigationStack {
                WebDAVLocationEditorView(
                    store: store,
                    locationID: destination.locationID,
                    isNew: destination.isNew
                )
            }
        }
        .sheet(isPresented: $isShowingLicenseSheet) {
            NavigationStack {
                ExternalStorageLicenseSheet()
            }
        }
        .alert("删除存储位置？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { location in
            Button("删除", role: .destructive) {
                store.remove(locationID: location.id)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { location in
            Text("将删除“\(location.name)”及其本机保存的登录凭据，不会删除服务器上的文件。")
        }
    }

    private func syncToFiles() {
        guard !isSyncingFiles else { return }
        isSyncingFiles = true
        Task {
            defer { isSyncingFiles = false }
            try? await filesCoordinator.sync(locations: store.locations)
        }
    }

    private func locationRow(_ location: WebDAVLocation) -> some View {
        HStack(spacing: 12) {
            Button {
                store.select(locationID: location.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.selectedLocationID == location.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.selectedLocationID == location.id ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(location.name)
                                .foregroundStyle(.primary)
                            Text(location.isSMB ? "SMB" : "WebDAV")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(location.baseURL.host ?? location.baseURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    store.select(locationID: location.id)
                } label: {
                    Label("设为当前位置", systemImage: "checkmark.circle")
                }
                Button {
                    editorDestination = LocationEditorDestination(locationID: location.id, isNew: false)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDeletion = location
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("\(location.name)操作")
        }
        .padding(.vertical, 2)
    }
}

private struct LocationEditorDestination: Identifiable {
    let locationID: UUID
    let isNew: Bool
    var id: UUID { locationID }
}

private struct WebDAVLocationEditorView: View {
    enum ProtocolType: String, CaseIterable, Identifiable {
        case webdav = "WebDAV"
        case smb = "SMB"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WebDAVSettingsStore

    let locationID: UUID
    let isNew: Bool
    @State private var protocolType: ProtocolType
    @State private var name: String
    @State private var baseURL: String
    @State private var username: String
    @State private var password: String
    @State private var allowsInsecureHTTP: Bool
    @State private var errorMessage: String?
    @State private var isTesting = false

    private var usesInsecureHTTP: Bool {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased() == "http"
    }

    init(store: WebDAVSettingsStore, locationID: UUID, isNew: Bool) {
        self.store = store
        self.locationID = locationID
        self.isNew = isNew
        let location = isNew ? nil : store.location(withID: locationID)
        let isSMB = location?.baseURL.scheme?.lowercased() == "smb"
        _protocolType = State(initialValue: isSMB ? .smb : .webdav)
        _name = State(initialValue: location?.name ?? "")
        _baseURL = State(initialValue: location?.baseURL.absoluteString ?? "")
        _username = State(initialValue: location?.username ?? "")
        _password = State(initialValue: location?.password ?? "")
        _allowsInsecureHTTP = State(initialValue: location?.baseURL.scheme?.lowercased() == "http")
    }

    private var requiresHTTPApproval: Bool {
        protocolType == .webdav && usesInsecureHTTP && !allowsInsecureHTTP
    }

    var body: some View {
        Form {
            Picker("协议", selection: $protocolType) {
                Text("WebDAV").tag(ProtocolType.webdav)
                Text("SMB").tag(ProtocolType.smb)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .onChange(of: protocolType) { _, newType in adjustDefaultURL(for: newType) }

            Section("连接") {
                LabeledContent("服务器地址") {
                    TextField("服务器地址", text: $baseURL, prompt: Text(protocolType == .smb ? "smb://" : "https://"))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .onChange(of: baseURL) {
                            allowsInsecureHTTP = false
                            errorMessage = nil
                        }
                }

                TextField("名称（可选）", text: $name)

                DisclosureGroup("地址格式与示例") {
                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        if protocolType == .smb {
                            Text("格式：smb://主机/共享名[/子文件夹]。匿名访问时可留空用户名。")
                            Text("示例：smb://nas.example.test/share")
                        } else {
                            Text("示例：https://dav.example.com/files/")
                            Text("若服务器要求应用专用密码，请用它代替账号密码。")
                        }
                        Text("名称留空时使用服务器主机名。")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, ESUI.Space.xs)
                }
            }

            Section("凭据") {
                TextField("用户名（可选）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("密码（可选）", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if protocolType == .webdav && usesInsecureHTTP {
                Section {
                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        Label("HTTP 连接未加密", systemImage: "exclamationmark.shield")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("凭据会以明文传输。请优先使用 HTTPS，仅在可信局域网内允许 HTTP。")
                            .font(.subheadline)
                    }
                    .padding(.vertical, ESUI.Space.xs)

                    Toggle("允许不安全的 HTTP", isOn: $allowsInsecureHTTP)
                        .tint(.orange)
                }
                .listRowBackground(Color.orange.opacity(0.14))
            }

            Section {
                Button(action: saveAndTest) {
                    Group {
                        if isTesting {
                            ProgressView("正在测试…").tint(.white)
                        } else {
                            Text("测试并保存").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(isTesting || requiresHTTPApproval || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(isTesting)
        .navigationTitle(isNew ? "添加位置" : "编辑位置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isTesting)
        .interactiveDismissDisabled(isTesting)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", systemImage: "xmark") { dismiss() }
                    .disabled(isTesting)
            }
        }
    }

    private func adjustDefaultURL(for type: ProtocolType) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .smb {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                if let url = URL(string: trimmed), let host = url.host {
                    baseURL = "smb://\(host)/share"
                }
            } else if trimmed.isEmpty {
                baseURL = "smb://"
            }
        } else {
            if trimmed.hasPrefix("smb://") {
                if let url = URL(string: trimmed), let host = url.host {
                    baseURL = "https://\(host)/dav"
                }
            } else if trimmed.isEmpty {
                baseURL = "https://"
            }
        }
    }

    private func saveAndTest() {
        errorMessage = nil
        if requiresHTTPApproval {
            errorMessage = "请先确认允许不安全的 HTTP。"
            return
        }

        var urlString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if protocolType == .smb, !urlString.lowercased().hasPrefix("smb://") {
            urlString = "smb://\(urlString)"
        }

        isTesting = true
        let result = store.makeLocation(
            id: locationID,
            name: name,
            baseURLString: urlString,
            username: username,
            password: password
        )
        switch result {
        case let .failure(error):
            isTesting = false
            errorMessage = error.localizedDescription
        case let .success(location):
            Task {
                do {
                    _ = try await WebDAVClient(configuration: location.configuration).list(path: "")
                    switch store.save(location: location) {
                    case .success:
                        isTesting = false
                        dismiss()
                    case let .failure(error):
                        isTesting = false
                        errorMessage = error.localizedDescription
                    }
                } catch is CancellationError {
                    isTesting = false
                } catch {
                    isTesting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ExternalStorageLicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(licenseContent)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private var licenseContent: String {
        if let url = Bundle.main.url(forResource: "ExternalStorageLicenses", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        return """
        EasySearch 外置存储 (SMB / WebDAV) 开源许可证声明

        1. AMSMB2
        Copyright (c) Amir Abbas Mousavian
        Licensed under the MIT License and uses libsmb2 (LGPL v2.1/v3).
        Source code: https://github.com/amosavian/AMSMB2

        AMSMB2 在本应用中作为动态链接库运行，其底层的 libsmb2 遵循 GNU Lesser General Public License (LGPL)。
        用户有权获取相应源码并重新链接该库。
        """
    }
}
