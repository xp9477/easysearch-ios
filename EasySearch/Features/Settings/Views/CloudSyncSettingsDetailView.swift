import SwiftUI

struct CloudSyncSettingsDetailView: View {
    @ObservedObject private var cloudViewModel = CloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""
    @State private var showsSignOutConfirmation = false

    private var currentAccount: String {
        let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "已登录" : email
    }

    private var loginUnavailable: Bool {
        cloudViewModel.isCloudBusy || cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudPassword.isEmpty
    }

    var body: some View {
        List {
            if cloudViewModel.isPreparingCloud {
                ProgressView("正在检查云端账号…")
            } else if !cloudViewModel.isCloudConfigured {
                Section {
                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        Text("仅本地保存").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("此版本未启用云端同步。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, ESUI.Space.xs)
                }
            } else if cloudViewModel.isCloudAuthenticated {
                accountSections
            } else {
                loginSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("云端同步")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cloudViewModel.prepareIfNeeded() }
        .confirmationDialog("退出云端登录？", isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
            Button("退出云端登录", role: .destructive) { signOut() }
        } message: {
            Text("本机数据会保留，重新登录前不会同步到云端。")
        }
    }

    @ViewBuilder
    private var accountSections: some View {
        if cloudViewModel.isCloudIdentityMismatch {
            Section {
                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Label("已暂停同步", systemImage: "exclamationmark.shield")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("当前账号无法同步此设备的数据。请退出后登录原账号。")
                        .font(.subheadline)
                }
                .padding(.vertical, ESUI.Space.xs)
                .listRowBackground(Color.orange.opacity(0.14))
            }
        }

        Section {
            LabeledContent("账号", value: currentAccount)

            if cloudViewModel.isCloudIdentityMismatch {
                Button("退出云端登录", role: .destructive, action: signOut)
                    .disabled(cloudViewModel.isCloudBusy)
            } else {
                Button {
                    Task { await cloudViewModel.syncNow() }
                } label: {
                    if cloudViewModel.isCloudBusy {
                        ProgressView("正在同步…")
                    } else {
                        Label("立即同步", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(cloudViewModel.isCloudBusy)

                cloudFeedback
            }
        }

        if !cloudViewModel.isCloudIdentityMismatch {
            Menu {
                Button("退出云端登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    showsSignOutConfirmation = true
                }
                .disabled(cloudViewModel.isCloudBusy)
            } label: {
                Label("账号操作", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var loginSections: some View {
        Section {
            TextField("邮箱", text: $cloudEmail)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .disabled(cloudViewModel.isCloudBusy)

            SecureField("密码", text: $cloudPassword)
                .textContentType(.password)
                .disabled(cloudViewModel.isCloudBusy)
        }

        Section {
            Button(action: signIn) {
                if cloudViewModel.isCloudBusy {
                    ProgressView("正在登录…")
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("登录")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loginUnavailable)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            cloudFeedback
        }
    }

    @ViewBuilder
    private var cloudFeedback: some View {
        if !cloudViewModel.isCloudBusy, let feedback = cloudViewModel.feedback {
            switch feedback {
            case let .failure(message):
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            case .syncCompleted:
                Label("同步完成", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .status:
                EmptyView()
            }
        }
    }

    private func signIn() {
        Task {
            await cloudViewModel.signIn(email: cloudEmail, password: cloudPassword)
            if cloudViewModel.isCloudAuthenticated { cloudPassword = "" }
        }
    }

    private func signOut() {
        Task {
            await cloudViewModel.signOut()
            cloudPassword = ""
        }
    }
}
