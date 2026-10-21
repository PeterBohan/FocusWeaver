import Foundation

struct FocusMetric: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let attentionScore: Double
    let blinkRate: Double
    let headPoseVariance: Double
    let distractionsDetected: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        attentionScore: Double,
        blinkRate: Double,
        headPoseVariance: Double,
        distractionsDetected: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.attentionScore = attentionScore
        self.blinkRate = blinkRate
        self.headPoseVariance = headPoseVariance
        self.distractionsDetected = distractionsDetected
    }
}

struct FocusSessionResult: Codable, Identifiable {
    let id: UUID
    let taskId: UUID?
    let startedAt: Date?
    let endedAt: Date?
    let plannedMinutes: Int
    let completedMinutes: Int
    let averageAttention: Double
    let interruptions: Int

    var adherence: Double {
        guard plannedMinutes > 0 else { return 0 }
        return Double(completedMinutes) / Double(plannedMinutes)
    }

    init(
        id: UUID = UUID(),
        taskId: UUID?,
        startedAt: Date? = .now,
        endedAt: Date? = .now,
        plannedMinutes: Int,
        completedMinutes: Int,
        averageAttention: Double,
        interruptions: Int
    ) {
        self.id = id
        self.taskId = taskId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.completedMinutes = completedMinutes
        self.averageAttention = averageAttention
        self.interruptions = interruptions
    }
}

struct UserProductivityProfile: Codable {
    var chronotype: String
    var averageAttention: Double
    var bestStartHour: Int
    var breakPreferenceMinutes: Int
    var streak: Int

    static let baseline = UserProductivityProfile(
        chronotype: "Builder",
        averageAttention: 0.62,
        bestStartHour: 9,
        breakPreferenceMinutes: 5,
        streak: 0
    )
}
