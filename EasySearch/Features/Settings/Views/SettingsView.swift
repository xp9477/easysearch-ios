import SwiftUI

/// 设置页面 - 提供配置刷新功能
struct SettingsView: View {
    @ObservedObject var viewModel: SearchViewModel
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 配置管理
                Section {
                    // 刷新按钮
                    Button {
                        Task {
                            await viewModel.refreshConfig()
                        }
                    } label: {
                        HStack {
                            Label("刷新配置文件", systemImage: "arrow.clockwise")
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.isRefreshing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isRefreshing)

                    // 当前引擎数量
                    HStack {
                        Label("搜索引擎数量", systemImage: "square.grid.3x3")
                        Spacer()
                        Text("\(viewModel.searchEngines.count)")
                            .foregroundStyle(.secondary)
                    }

                    // 上次刷新时间
                    if let lastRefresh = viewModel.lastRefreshDate {
                        HStack {
                            Label("上次刷新", systemImage: "clock")
                            Spacer()
                            Text(lastRefresh, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("配置管理")
                } footer: {
                    Text("配置文件存储在本地，只有手动点击刷新时才会从网络更新。")
                }

                Section {
                    if let message = cloudViewModel.cloudStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("当前状态", systemImage: "icloud")
                                .font(.subheadline.weight(.semibold))
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !cloudViewModel.isCloudConfigured {
                        Text("请在 Info.plist 配置 SUPABASE_URL 与 SUPABASE_PUBLISHABLE_KEY。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if cloudViewModel.isCloudAuthenticated {
                        HStack {
                            Label("当前账号", systemImage: "person.crop.circle")
                            Spacer()
                            Text({
                                let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                return email.isEmpty ? "已登录" : email
                            }())
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                await cloudViewModel.syncNow()
                            }
                        } label: {
                            HStack {
                                Label("同步隐藏空间数据", systemImage: "arrow.triangle.2.circlepath")
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
                } header: {
                    Text("云端同步")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("刷新成功", isPresented: $viewModel.refreshSuccess) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("已成功加载 \(viewModel.searchEngines.count) 个搜索引擎配置")
            }
            .alert("刷新失败", isPresented: .init(
                get: { viewModel.refreshError != nil },
                set: { if !$0 { viewModel.refreshError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                if let error = viewModel.refreshError {
                    Text(error)
                }
            }
            .task {
                await cloudViewModel.prepareIfNeeded()
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: SearchViewModel())
}
