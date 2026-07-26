import SwiftUI

struct HiddenSpaceSettingsHubView: View {
    var body: some View {
        List {
            NavigationLink {
                HiddenJavDBSettingsDetailView()
            } label: {
                Label("javdb 设置", systemImage: "film.stack")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐藏空间设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HiddenJavDBSettingsDetailView: View {
    @State private var showJavDBDetailsByDefault = HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault
    @State private var missAVDomain = HiddenSpaceSettingsStore.shared.load().missAVDomain

    var body: some View {
        List {
            Section {
                Toggle("默认展开详细信息", isOn: $showJavDBDetailsByDefault)
            } header: {
                Text("详情")
            } footer: {
                Text("详细信息可在影片卡片与详情页随时切换显示。")
            }

            Section {
                TextField("miss 域名，例如 missav.ws", text: $missAVDomain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                LabeledContent("当前生效") {
                    Text(HiddenMissAVDomainConfiguration.resolvedHost(from: missAVDomain))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !missAVDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("恢复默认域名", role: .destructive) {
                        missAVDomain = ""
                    }
                }
            } header: {
                Text("MissAV")
            } footer: {
                Text("支持直接输入域名或完整 URL；留空时回退默认域名。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("javdb 设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let settings = HiddenSpaceSettingsStore.shared.load()
            showJavDBDetailsByDefault = settings.showJavDBDetailsByDefault
            missAVDomain = settings.missAVDomain
        }
        .onChange(of: showJavDBDetailsByDefault) { enabled in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.showJavDBDetailsByDefault = enabled
            }
        }
        .onChange(of: missAVDomain) { domain in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.missAVDomain = domain
            }
        }
    }
}
