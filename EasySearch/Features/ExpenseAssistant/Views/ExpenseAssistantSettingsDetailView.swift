import SwiftUI
import UIKit

struct ExpenseAssistantSettingsDetailView: View {
    @ObservedObject private var notificationManager = ExpenseAssistantNotificationManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                HStack {
                    Text("通知权限")
                    Spacer()
                    ESStatusBadge(text: notificationManager.statusText, tone: authTone)
                }

                switch notificationManager.authorizationStatus {
                case .notDetermined:
                    Button {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    } label: {
                        Label("开启提醒通知", systemImage: "bell.badge")
                    }

                case .denied:
                    Button {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(settingsURL)
                    } label: {
                        Label("前往系统设置开启通知", systemImage: "gearshape")
                    }

                case .authorized, .provisional, .ephemeral:
                    Button {
                        Task {
                            await notificationManager.refreshStateAndSchedules()
                        }
                    } label: {
                        Label("立即刷新提醒计划", systemImage: "arrow.clockwise")
                    }

                @unknown default:
                    EmptyView()
                }
            } header: {
                Text("单据逾期提醒")
            } footer: {
                Text("开启通知后，系统将在月底及出差结束后提醒你及时提交未完成报销单。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("报销助手设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.configure()
        }
    }

    private var authTone: ESStatusBadge.Tone {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .success
        case .denied:
            return .danger
        case .notDetermined:
            return .warning
        @unknown default:
            return .neutral
        }
    }
}
