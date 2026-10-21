import Foundation

struct TaskCompletionRecord: Codable {
    var completedAt: Date
    var suggestionKey: String
}

struct SessionPersistedState: Codable {
    var profile: UserProductivityProfile
    var sessionHistory: [FocusSessionResult]
    var taskCompletions: [UUID: TaskCompletionRecord]?
}

final class SessionDataStore {
    private let storeURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "session_state.json", directory storeDirectory: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = storeDirectory ?? directory.appendingPathComponent("FocusWeaver", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        storeURL = folder.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func persist(profile: UserProductivityProfile, sessionHistory: [FocusSessionResult], taskCompletions: [UUID: TaskCompletionRecord]) {
        let payload = SessionPersistedState(profile: profile, sessionHistory: Array(sessionHistory.suffix(50)), taskCompletions: taskCompletions)
        do {
            let data = try encoder.encode(payload)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Session persist error: \(error.localizedDescription)")
        }
    }

    func load() -> SessionPersistedState? {
        guard let data = try? Data(contentsOf: storeURL) else {
            return nil
        }
        do {
            return try decoder.decode(SessionPersistedState.self, from: data)
        } catch {
            print("Session load error: \(error.localizedDescription)")
            return nil
        }
    }
}
