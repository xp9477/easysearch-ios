import SwiftUI

struct WebDAVSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WebDAVSettingsStore
    @State private var baseURL: String
    @State private var username: String
    @State private var password: String
    @State private var allowsInsecureHTTP: Bool
    @State private var errorMessage: String?
    @State private var isTesting = false

    private var usesInsecureHTTP: Bool {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased() == "http"
    }

    init(store: WebDAVSettingsStore = .shared) {
        self.store = store
        _baseURL = State(initialValue: store.configuration?.baseURL.absoluteString ?? "")
        _username = State(initialValue: store.configuration?.username ?? "")
        _password = State(initialValue: store.configuration?.password ?? "")
        _allowsInsecureHTTP = State(initialValue: store.configuration?.baseURL.scheme?.lowercased() == "http")
    }

    var body: some View {
        Form {
            Section {
                TextField("服务器地址，例如 https://dav.example.com/remote.php/dav/files/user", text: $baseURL)
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
                Text("建议使用 HTTPS；HTTP 仅适用于局域网。建议为 WebDAV 创建独立的应用专用密码。")
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

                if store.configuration != nil {
                    Button("清除连接", role: .destructive) {
                        store.clear()
                        dismiss()
                    }
                    .disabled(isTesting)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("WebDAV 设置")
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
        let result = store.makeConfiguration(baseURLString: baseURL, username: username, password: password)
        switch result {
        case let .failure(error):
            isTesting = false
            errorMessage = error.localizedDescription
        case let .success(configuration):
            Task {
                do {
                    _ = try await WebDAVClient(configuration: configuration).list(path: "")
                    await MainActor.run {
                        switch store.save(configuration: configuration) {
                        case .success:
                            isTesting = false
                            dismiss()
                        case let .failure(error):
                            isTesting = false
                            errorMessage = error.localizedDescription
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run { isTesting = false }
                } catch {
                    await MainActor.run {
                        isTesting = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

}
