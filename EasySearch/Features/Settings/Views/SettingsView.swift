import SwiftUI

struct SettingsView: View {
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""
    @State private var deepSeekAPIKey = ""
    @State private var deepSeekModel = ""
    @State private var deepSeekTargetLanguage: ImageTranslateTargetLanguage = .simplifiedChinese
    @State private var deepSeekStatusMessage: String?

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where !shortVersion.isEmpty && !buildVersion.isEmpty:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _) where !shortVersion.isEmpty:
            return shortVersion
        case let (_, buildVersion?) where !buildVersion.isEmpty:
            return buildVersion
        default:
            return "未知"
        }
    }

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

    private var deepSeekConfigurationStatusText: String {
        deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : "已配置"
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

                Section {
                    HStack {
                        Label("当前状态", systemImage: "sparkles")
                        Spacer()
                        Text(deepSeekConfigurationStatusText)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("DeepSeek API Key", text: $deepSeekAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("模型（默认 deepseek-chat）", text: $deepSeekModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("默认目标语言", selection: $deepSeekTargetLanguage) {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Button {
                        saveDeepSeekConfiguration()
                    } label: {
                        Label("保存 DeepSeek 配置", systemImage: "tray.and.arrow.down")
                    }

                    if let deepSeekStatusMessage,
                       !deepSeekStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(deepSeekStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("DeepSeek")
                } footer: {
                    Text("截图翻译和邮件助手共用这份 DeepSeek 配置。API Key 为空时保存，会清除本地已存配置；模型默认使用 deepseek-chat。")
                }

                Section("关于") {
                    HStack {
                        Text("版本号")
                        Spacer()
                        Text(appVersionText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await cloudViewModel.prepareIfNeeded()
                loadDeepSeekConfiguration()
            }
        }
    }

    private func loadDeepSeekConfiguration() {
        let configuration = ImageTranslateConfigurationStore.shared.loadConfiguration()
        deepSeekAPIKey = configuration.apiKey
        deepSeekModel = configuration.model
        deepSeekTargetLanguage = configuration.targetLanguage
    }

    private func saveDeepSeekConfiguration() {
        do {
            try ImageTranslateConfigurationStore.shared.saveConfiguration(
                apiKey: deepSeekAPIKey,
                model: deepSeekModel,
                targetLanguage: deepSeekTargetLanguage
            )
            loadDeepSeekConfiguration()
            deepSeekStatusMessage = deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "已清除本地 DeepSeek API Key，OCR 仍可单独使用。"
                : "DeepSeek 配置已保存，截图翻译和邮件助手都可以直接使用。"
        } catch {
            deepSeekStatusMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
}
