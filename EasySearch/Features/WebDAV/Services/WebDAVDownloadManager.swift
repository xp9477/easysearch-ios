import Combine
import Foundation

struct WebDAVDownloadJob: Identifiable, Equatable {
    enum State: Equatable {
        case queued
        case preparing
        case downloading
        case cancelling
        case completed(URL)
        case failed(String)
        case cancelled

        var isActive: Bool {
            switch self {
            case .queued, .preparing, .downloading, .cancelling:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        }
    }

    let id: UUID
    let locationID: UUID?
    let locationName: String
    let item: WebDAVItem
    let createdAt: Date
    var state: State
    var progress: WebDAVTransferProgress?
}

@MainActor
final class WebDAVDownloadManager: ObservableObject {
    static let shared = WebDAVDownloadManager()

    @Published private(set) var jobs: [WebDAVDownloadJob] = []

    private struct Request {
        let configuration: WebDAVConfiguration
        let item: WebDAVItem
    }

    private var requests: [UUID: Request] = [:]
    private var runningJobID: UUID?
    private var runningTask: Task<Void, Never>?

    var activeCount: Int {
        jobs.filter { $0.state.isActive }.count
    }

    @discardableResult
    func enqueue(configuration: WebDAVConfiguration, item: WebDAVItem) -> UUID {
        if let existing = jobs.first(where: {
            $0.locationID == configuration.locationID && $0.item.path == item.path && $0.state.isActive
        }) {
            return existing.id
        }

        let id = UUID()
        let job = WebDAVDownloadJob(
            id: id,
            locationID: configuration.locationID,
            locationName: configuration.displayName.isEmpty
                ? (configuration.baseURL.host ?? "WebDAV")
                : configuration.displayName,
            item: item,
            createdAt: Date(),
            state: .queued,
            progress: nil
        )
        jobs.append(job)
        requests[id] = Request(configuration: configuration, item: item)
        startNextIfNeeded()
        return id
    }

    func cancel(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].state.isActive else {
            return
        }
        if runningJobID == jobID {
            jobs[index].state = .cancelling
            runningTask?.cancel()
        } else {
            jobs[index].state = .cancelled
            startNextIfNeeded()
        }
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), requests[jobID] != nil else {
            return
        }
        switch jobs[index].state {
        case .failed, .cancelled:
            jobs[index].state = .queued
            jobs[index].progress = nil
            startNextIfNeeded()
        case .queued, .preparing, .downloading, .cancelling, .completed:
            break
        }
    }

    func remove(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }), !job.state.isActive else { return }
        jobs.removeAll(where: { $0.id == jobID })
        requests.removeValue(forKey: jobID)
    }

    func clearFinished() {
        let finishedIDs = Set(jobs.filter { !$0.state.isActive }.map(\.id))
        jobs.removeAll(where: { finishedIDs.contains($0.id) })
        for id in finishedIDs {
            requests.removeValue(forKey: id)
        }
    }

    private func startNextIfNeeded() {
        guard runningJobID == nil,
              let index = jobs.firstIndex(where: { $0.state == .queued }),
              let request = requests[jobs[index].id] else { return }

        let jobID = jobs[index].id
        jobs[index].state = .preparing
        runningJobID = jobID
        runningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let localURL = try await WebDAVClient(configuration: request.configuration).download(
                    item: request.item,
                    into: WebDAVLocalFileStore.rootURL
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.update(jobID: jobID, progress: progress)
                    }
                }
                guard !Task.isCancelled else {
                    finish(jobID: jobID, state: .cancelled)
                    return
                }
                finish(jobID: jobID, state: .completed(localURL))
            } catch {
                if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled {
                    finish(jobID: jobID, state: .cancelled)
                } else {
                    finish(jobID: jobID, state: .failed(error.localizedDescription))
                }
            }
        }
    }

    private func update(jobID: UUID, progress: WebDAVTransferProgress) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].state.isActive,
              jobs[index].state != .cancelling else {
            return
        }
        jobs[index].state = .downloading
        jobs[index].progress = progress
    }

    private func finish(jobID: UUID, state: WebDAVDownloadJob.State) {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].state = state
        }
        if case .completed = state {
            requests.removeValue(forKey: jobID)
        }
        if runningJobID == jobID {
            runningJobID = nil
            runningTask = nil
        }
        startNextIfNeeded()
    }
}
