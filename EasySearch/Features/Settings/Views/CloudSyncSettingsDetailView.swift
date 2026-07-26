import SwiftUI

struct CloudSyncSettingsDetailView: View {
    @ObservedObject private var cloudViewModel = CloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""

    private var cloudInlineMessage: String? {
        guard let message = cloudViewModel.cloudStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return message
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("状态", systemImage: cloudViewModel.isCloudAuthenticated ? "icloud.fill" : "icloud")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if cloudViewModel.isCloudConfigured {
                    if cloudViewModel.isCloudAuthenticated {
                        HStack {
                            Label("账号", systemImage: "person.crop.circle")
                            Spacer()
                            Text(currentAccountText)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button {
                            Task {
                                await cloudViewModel.syncNow()
                            }
                        } label: {
                            HStack {
                                Label("同步", systemImage: "arrow.clockwise")
                                Spacer()
                                if cloudViewModel.isCloudBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(cloudViewModel.isCloudBusy)

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
                        .disabled(
                            cloudViewModel.isCloudBusy ||
                            cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            cloudPassword.isEmpty
                        )

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
                        .disabled(
                            cloudViewModel.isCloudBusy ||
                            cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            cloudPassword.isEmpty
                        )
                    }
                }

                if let cloudInlineMessage {
                    Text(cloudInlineMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("会同步：隐藏空间收藏/播放点、UT 记录、青龙面板配置（不含密钥）。")
                Text("仅本地：训练记录、报销、翻译/邮件历史、WebDAV 配置与文件、搜索引擎配置。")
                Text("隐藏空间为低曝光入口（连点解锁 + 后台遮罩），不是加密保险箱。")
            } header: {
                Text("数据说明")
            } footer: {
                Text("多设备合并以当前实现为准（按 ID 去重合并后写回）。")
            }
        }
        .navigationTitle("云端同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloudViewModel.prepareIfNeeded()
        }
    }

    private var statusText: String {
        if !cloudViewModel.isCloudConfigured {
            return "仅本地"
        }
        return cloudViewModel.isCloudAuthenticated ? "已登录" : "未登录"
    }

    private var currentAccountText: String {
        let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "已登录" : email
    }
}
