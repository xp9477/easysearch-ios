import Foundation
import SwiftUI

struct WebDAVSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WebDAVSettingsStore
    let showsCloseButton: Bool

    @State private var editorDestination: LocationEditorDestination?
    @State private var pendingDeletion: WebDAVLocation?

    init(store: WebDAVSettingsStore = .shared, showsCloseButton: Bool = false) {
        self.store = store
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        List {
            Section {
                if store.locations.isEmpty {
                    Text("还没有 WebDAV 位置")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.locations) { location in
                        locationRow(location)
                    }
                }

                Button {
                    editorDestination = LocationEditorDestination(locationID: UUID(), isNew: true)
                } label: {
                    Label("添加 WebDAV 位置", systemImage: "plus")
                }
            } header: {
                Text("WebDAV 位置")
            } footer: {
                Text("当前位置用于文件浏览和从分享菜单上传；可以随时在文件管理页面切换。")
            }

            Section("浏览") {
                Toggle("显示隐藏文件夹", isOn: Binding(
                    get: { store.showsHiddenFolders },
                    set: { store.setShowsHiddenFolders($0) }
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("WebDAV 设置")
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
        .alert("删除 WebDAV 位置？", isPresented: Binding(
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
                        Text(location.name)
                            .foregroundStyle(.primary)
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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WebDAVSettingsStore

    let locationID: UUID
    let isNew: Bool
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
        _name = State(initialValue: location?.name ?? "")
        _baseURL = State(initialValue: location?.baseURL.absoluteString ?? "")
        _username = State(initialValue: location?.username ?? "")
        _password = State(initialValue: location?.password ?? "")
        _allowsInsecureHTTP = State(initialValue: location?.baseURL.scheme?.lowercased() == "http")
    }

    var body: some View {
        Form {
            Section {
                TextField("位置名称，例如 家庭 NAS", text: $name)

                TextField("服务器地址", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                TextField("用户名（可选）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("密码或应用专用密码", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if usesInsecureHTTP {
                    Toggle("允许不安全的 HTTP 连接", isOn: $allowsInsecureHTTP)
                        .tint(.orange)
                }
            } header: {
                Text("连接配置")
            } footer: {
                Text("建议使用 HTTPS；HTTP 仅适用于可信局域网。位置名称留空时使用服务器域名。")
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

    private func saveAndTest() {
        errorMessage = nil
        guard !usesInsecureHTTP || allowsInsecureHTTP else {
            errorMessage = "HTTP 会以明文传输 WebDAV 凭据。确认这是可信局域网后，再开启“不安全的 HTTP 连接”。"
            return
        }
        isTesting = true
        let result = store.makeLocation(
            id: locationID,
            name: name,
            baseURLString: baseURL,
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
