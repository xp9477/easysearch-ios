import Foundation

enum WebDAVLocalFileStore {
    struct StagedUpload {
        let localURL: URL
        let remoteFileName: String
        fileprivate let directoryURL: URL
    }

    struct StagedEdit {
        let localURL: URL
        fileprivate let directoryURL: URL
    }

    static var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func makePreviewDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches
            .appendingPathComponent("WebDAVPreviews", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        return directory
    }

    static func removePreview(containing fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebDAVPreviews", isDirectory: true)
        guard directory.path.hasPrefix(caches.path + "/") else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func destinationURL(for remotePath: String) -> URL {
        let components = remotePath
            .split(separator: "/")
            .map { sanitizedFileName(String($0)) }
        return components.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    static func sanitizedFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            return "未命名文件"
        }
        return trimmed
    }

    static func stageForUpload(_ url: URL) throws -> StagedUpload {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("EasySearchWebDAVUploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = sanitizedFileName(url.lastPathComponent)
        let destination = directory.appendingPathComponent(fileName)
        do {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                try fileManager.copyItem(at: url, to: destination)
            } else {
                try fileManager.copyItem(at: url, to: destination)
            }
            return StagedUpload(localURL: destination, remoteFileName: fileName, directoryURL: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    static func removeStagedUpload(_ stagedUpload: StagedUpload) {
        try? FileManager.default.removeItem(at: stagedUpload.directoryURL)
    }

    static func stageEditedFile(_ url: URL) throws -> StagedEdit {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("WebDAVEdits", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(sanitizedFileName(url.lastPathComponent))
        do {
            try fileManager.copyItem(at: url, to: target)
            return StagedEdit(localURL: target, directoryURL: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    static func removeStagedEdit(_ stagedEdit: StagedEdit) {
        try? FileManager.default.removeItem(at: stagedEdit.directoryURL)
    }

    static func uniqueURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
