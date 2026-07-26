import SwiftUI

enum AISettingsEntry {
    case imageTranslate
    case emailAssistant

    var title: String {
        switch self {
        case .imageTranslate:
            return "AI 服务"
        case .emailAssistant:
            return "邮件助手"
        }
    }

    var showsTargetLanguage: Bool {
        self == .imageTranslate
    }
}

struct AISettingsDetailView: View {
    let entry: AISettingsEntry

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var targetLanguage: ImageTranslateTargetLanguage = .simplifiedChinese
    @State private var statusMessage: String?

    private var configurationStatusText: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : "已配置"
    }

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "状态", value: configurationStatusText)

                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                SecureField("AI API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("模型 ID", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveConfiguration()
                } label: {
                    Label("保存", systemImage: "tray.and.arrow.down")
                }

                if let statusMessage,
                   !statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("支持 OpenAI 兼容接口。CLIProxyAPI 可填写为你的服务地址，例如 http://127.0.0.1:8080/v1，模型填写你在代理里要转发的模型 ID。")
            }

            if entry.showsTargetLanguage {
                Section {
                    Picker("默认目标语言", selection: $targetLanguage) {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadConfiguration()
        }
    }

    private func loadConfiguration() {
        let configuration = ImageTranslateConfigurationStore.shared.loadConfiguration()
        baseURL = configuration.baseURL
        apiKey = configuration.apiKey
        model = configuration.model
        targetLanguage = configuration.targetLanguage
    }

    private func saveConfiguration() {
        do {
            try ImageTranslateConfigurationStore.shared.saveConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                targetLanguage: targetLanguage
            )
            loadConfiguration()
            statusMessage = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "已清除本地 AI API Key。"
                : "AI 配置已保存，翻译和邮件助手都会同步使用。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
