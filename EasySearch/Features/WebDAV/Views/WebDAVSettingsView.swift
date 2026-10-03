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
            Section {
                if store.locations.isEmpty {
                    Text("还没有配置存储位置")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.locations) { location in
                        locationRow(location)
                    }
                }

                Button {
                    editorDestination = LocationEditorDestination(locationID: UUID(), isNew: true)
                } label: {
                    Label("添加存储位置", systemImage: "plus")
                }
            } header: {
                Text("存储位置")
            } footer: {
                Text("当前位置用于文件浏览和从分享菜单上传；可以随时在文件管理页面切换。")
            }

            Section("系统“文件” App (Files)") {
                if let status = filesCoordinator.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if filesCoordinator.syncedDomainCount > 0 {
                    Text("已同步 \(filesCoordinator.syncedDomainCount) 个存储位置至系统文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = filesCoordinator.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        isSyncingFiles = true
                        defer { isSyncingFiles = false }
                        try? await filesCoordinator.sync(locations: store.locations)
                    }
                } label: {
                    HStack {
                        Label("同步到系统“文件” App", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isSyncingFiles { ProgressView() }
                    }
                }
            }

            Section("浏览") {
                Toggle("显示隐藏文件夹", isOn: Binding(
                    get: { store.showsHiddenFolders },
                    set: { store.setShowsHiddenFolders($0) }
                ))
            }

            Section("开源许可") {
                Button {
                    isShowingLicenseSheet = true
                } label: {
                    HStack {
                        Label("开源协议告知 (AMSMB2 / LGPL)", systemImage: "doc.text")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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

    var body: some View {
        Form {
            Section("协议选择") {
                Picker("协议类型", selection: $protocolType) {
                    Text("WebDAV (HTTP/HTTPS)").tag(ProtocolType.webdav)
                    Text("SMB (Windows / NAS 共享)").tag(ProtocolType.smb)
                }
                .pickerStyle(.segmented)
                .onChange(of: protocolType) { newType in
                    adjustDefaultURL(for: newType)
                }
            }

            Section {
                TextField(protocolType == .smb ? "例如 局域网 NAS" : "例如 云端网盘", text: $name)

                TextField(serverAddressPlaceholder, text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                TextField(protocolType == .smb ? "用户名（匿名留空）" : "用户名（可选）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("密码或应用专用密码", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if protocolType == .webdav && usesInsecureHTTP {
                    Toggle("允许不安全的 HTTP 连接", isOn: $allowsInsecureHTTP)
                        .tint(.orange)
                }
            } header: {
                Text("连接配置")
            } footer: {
                Text(connectionFooterText)
            }

            Section {
                Button {
                    saveAndTest()
                } label: {
                    HStack {
                        Label("保存并测试连接", systemImage: "checkmark.circle")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(isNew ? "添加位置" : "编辑位置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isTesting)
        .interactiveDismissDisabled(isTesting)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isTesting)
            }
        }
    }

    private var serverAddressPlaceholder: String {
        switch protocolType {
        case .webdav:
            return "https://dav.example.com/files/"
        case .smb:
            return "smb://192.168.1.100/share"
        }
    }

    private var connectionFooterText: String {
        switch protocolType {
        case .webdav:
            return "建议使用 HTTPS；HTTP 仅适用于可信局域网。位置名称留空时使用服务器域名。"
        case .smb:
            return "SMB 地址格式为 smb://主机/共享名[/子文件夹]，例如 smb://192.168.1.100/data。支持 Windows 共享、群晖、TrueNAS 等。"
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
        if protocolType == .webdav, usesInsecureHTTP, !allowsInsecureHTTP {
            errorMessage = "HTTP 会以明文传输凭据。确认这是可信局域网后，再开启“不安全的 HTTP 连接”。"
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
