import Foundation
import SwiftUI

struct WebDAVMovePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let configuration: WebDAVConfiguration
    let movingItem: WebDAVItem
    let onSelectDirectory: (String) -> Void

    @State private var currentBrowsePath: String
    @State private var directories: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentParentPath: String {
        let parts = movingItem.path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private var isAlreadyInCurrentDirectory: Bool {
        normalize(currentBrowsePath) == normalize(currentParentPath)
    }

    init(
        configuration: WebDAVConfiguration,
        movingItem: WebDAVItem,
        initialDirectory: String,
        onSelectDirectory: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.movingItem = movingItem
        self._currentBrowsePath = State(initialValue: initialDirectory)
        self.onSelectDirectory = onSelectDirectory
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentBrowsePath.isEmpty ? "根目录" : currentBrowsePath)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if isAlreadyInCurrentDirectory {
                            Text("项目当前所在目录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if !currentBrowsePath.isEmpty {
                    Button {
                        currentBrowsePath = parentPath(of: currentBrowsePath)
                    } label: {
                        Label("返回上一级", systemImage: "chevron.left")
                    }
                }
            } header: {
                Text("当前目标位置")
            }

            Section {
                if isLoading && directories.isEmpty {
                    HStack {
                        ProgressView()
                        Text("正在读取子目录…")
                            .foregroundStyle(.secondary)
                    }
                } else if directories.isEmpty {
                    Text("当前目录没有子文件夹")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(directories) { dir in
                        Button {
                            currentBrowsePath = dir.path
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.yellow)
                                Text(dir.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("进入子文件夹")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("移动到…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("移动到此处") {
                    onSelectDirectory(currentBrowsePath)
                    dismiss()
                }
                .disabled(isAlreadyInCurrentDirectory || isLoading)
            }
        }
        .task(id: currentBrowsePath) {
            await loadDirectories()
        }
    }

    private func loadDirectories() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let items = try await WebDAVClient(configuration: configuration).list(path: currentBrowsePath)
            // Filter to only directories, and exclude movingItem itself if it is a directory
            let forbiddenPrefix = movingItem.isDirectory ? movingItem.path : ""
            directories = items.filter { item in
                guard item.isDirectory else { return false }
                if movingItem.isDirectory {
                    if item.path == forbiddenPrefix || item.path.hasPrefix(forbiddenPrefix + "/") {
                        return false
                    }
                }
                return true
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parentPath(of path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    }
}
