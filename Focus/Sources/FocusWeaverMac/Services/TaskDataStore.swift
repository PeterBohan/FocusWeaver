import Foundation

final class TaskDataStore {
    private let storeURL: URL
    private let dismissedStoreURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "tasks.json", directory storeDirectory: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = storeDirectory ?? directory.appendingPathComponent("FocusWeaver", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        storeURL = folder.appendingPathComponent(filename)
        dismissedStoreURL = folder.appendingPathComponent("dismissed_task_keys.json")
        encoder.outputFormatting = [.prettyPrinted]
    }

    func persist(_ tasks: [TaskItem]) {
        do {
            let data = try encoder.encode(tasks)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Task persist error: \(error.localizedDescription)")
        }
    }

    func loadTasks() -> [TaskItem]? {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? decoder.decode([TaskItem].self, from: data)
    }

    func persistDismissedTaskKeys(_ keys: Set<String>) {
        do {
            let sortedKeys = Array(keys).sorted()
            let data = try encoder.encode(sortedKeys)
            try data.write(to: dismissedStoreURL, options: .atomic)
        } catch {
            print("Dismissed task key persist error: \(error.localizedDescription)")
        }
    }

    func loadDismissedTaskKeys() -> Set<String> {
        guard FileManager.default.fileExists(atPath: dismissedStoreURL.path),
              let data = try? Data(contentsOf: dismissedStoreURL) else {
            return []
        }
        do {
            let keys = try decoder.decode([String].self, from: data)
            return Set(keys)
        } catch {
            print("Dismissed task key load error: \(error.localizedDescription)")
            return []
        }
    }
}
