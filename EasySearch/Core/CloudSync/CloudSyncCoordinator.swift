import Foundation

struct CloudSyncCollectionReport {
    let label: String
    let count: Int
    let unit: String

    var summaryText: String {
        "\(label) \(count)\(unit)"
    }
}

struct CloudSyncCollection<Item> {
    let label: String
    let unit: String
    let loadLocal: () -> [Item]
    let fetchRemote: () async throws -> [Item]
    let saveLocal: ([Item]) -> Void
    let upsertRemote: ([Item]) async throws -> Void
    let merge: ([Item], [Item]) -> [Item]

    func eraseToAnyCollection() -> AnyCloudSyncCollection {
        AnyCloudSyncCollection(sync: sync)
    }

    private func sync() async throws -> CloudSyncCollectionReport {
        let merged = merge(try await fetchRemote(), loadLocal())
        saveLocal(merged)
        try await upsertRemote(merged)
        return CloudSyncCollectionReport(label: label, count: merged.count, unit: unit)
    }
}

struct AnyCloudSyncCollection {
    private let runSync: () async throws -> CloudSyncCollectionReport

    init(sync: @escaping () async throws -> CloudSyncCollectionReport) {
        runSync = sync
    }

    func sync() async throws -> CloudSyncCollectionReport {
        try await runSync()
    }
}

enum CloudSyncCoordinator {
    static func sync(_ collections: [AnyCloudSyncCollection]) async throws -> [CloudSyncCollectionReport] {
        var reports: [CloudSyncCollectionReport] = []
        reports.reserveCapacity(collections.count)

        for collection in collections {
            reports.append(try await collection.sync())
        }

        return reports
    }
}
