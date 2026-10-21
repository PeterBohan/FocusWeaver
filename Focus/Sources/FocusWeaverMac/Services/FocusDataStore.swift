import Foundation

final class FocusDataStore {
    private let storeURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "focus_metrics.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = directory.appendingPathComponent("FocusWeaver", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        storeURL = folder.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func persistMetrics(_ metrics: [FocusMetric]) {
        do {
            let data = try encoder.encode(metrics)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Persist error: \(error.localizedDescription)")
        }
    }

    func loadMetrics() -> [FocusMetric] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            return try decoder.decode([FocusMetric].self, from: data)
        } catch {
            print("Load error: \(error.localizedDescription)")
            return []
        }
    }
}
