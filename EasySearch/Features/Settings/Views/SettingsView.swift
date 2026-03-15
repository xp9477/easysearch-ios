import SwiftUI

struct SettingsView: View {
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""

    private var cloudInlineMessage: String? {
        guard let message = cloudViewModel.cloudStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        if message.contains("失败") || message.contains("请先") || message.contains("确认") || message.contains("未配置") {
            return message
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                if cloudViewModel.isCloudConfigured {
                    Section {
                        if cloudViewModel.isCloudAuthenticated {
                        HStack {
                            Label("当前账号", systemImage: "person.crop.circle")
                            Spacer()
                            Text({
                                let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                return email.isEmpty ? "已登录" : email
                            }())
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            Task {
                                await cloudViewModel.signOut()
                            }
                        } label: {
                            Label("退出云端登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(cloudViewModel.isCloudBusy)
                        } else {
                            TextField("邮箱", text: $cloudEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        SecureField("密码", text: $cloudPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                await cloudViewModel.signIn(email: cloudEmail, password: cloudPassword)
                                if cloudViewModel.isCloudAuthenticated {
                                    cloudPassword = ""
                                }
                            }
                        } label: {
                            HStack {
                                Label("登录", systemImage: "person.crop.circle.badge.checkmark")
                                Spacer()
                                if cloudViewModel.isCloudBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(cloudViewModel.isCloudBusy || cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudPassword.isEmpty)

                        Button {
                            Task {
                                await cloudViewModel.signUp(email: cloudEmail, password: cloudPassword)
                                if cloudViewModel.isCloudAuthenticated {
                                    cloudPassword = ""
                                }
                            }
                        } label: {
                            Label("注册", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(cloudViewModel.isCloudBusy || cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudPassword.isEmpty)
                        }

                        if let cloudInlineMessage {
                            Text(cloudInlineMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("账号")
                    } footer: {
                        Text("登录后会自动同步本地数据；网络恢复后会在后续操作中继续尝试同步。")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await cloudViewModel.prepareIfNeeded()
            }
        }
    }
}

#Preview {
    SettingsView()
}
