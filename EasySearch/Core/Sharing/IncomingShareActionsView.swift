import SwiftUI

enum IncomingShareAction: String, CaseIterable, Identifiable {
    case storeToWebDAV
    case reserved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storeToWebDAV:
            return "存储到 WebDAV"
        case .reserved:
            return "其他功能"
        }
    }

    var systemImage: String {
        switch self {
        case .storeToWebDAV:
            return "externaldrive.badge.plus"
        case .reserved:
            return "ellipsis.circle"
        }
    }
}

struct IncomingShareActionsView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [SharedInboxItem]
    let onConsumed: ([SharedInboxItem]) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("已接收") {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayName)
                                    .lineLimit(2)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("选择操作") {
                    NavigationLink {
                        WebDAVShareUploadView(items: items) {
                            onConsumed(items)
                            dismiss()
                        }
                    } label: {
                        Label(IncomingShareAction.storeToWebDAV.title, systemImage: IncomingShareAction.storeToWebDAV.systemImage)
                    }

                    HStack {
                        Label(IncomingShareAction.reserved.title, systemImage: IncomingShareAction.reserved.systemImage)
                        Spacer()
                        Text("预留")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button("丢弃这些内容", role: .destructive) {
                        onConsumed(items)
                        dismiss()
                    }
                }
            }
            .navigationTitle("处理分享内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后处理") { dismiss() }
                }
            }
        }
    }
}
