import Foundation

enum PomodoroPhase: String, Codable {
    case focus
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

struct PomodoroSegment: Identifiable, Codable {
    let id: UUID
    let phase: PomodoroPhase
    let durationMinutes: Int
    var completed: Bool

    init(id: UUID = UUID(), phase: PomodoroPhase, durationMinutes: Int, completed: Bool = false) {
        self.id = id
        self.phase = phase
        self.durationMinutes = durationMinutes
        self.completed = completed
    }
}

struct ScheduleBlock: Identifiable, Codable {
    let id: UUID
    var task: TaskItem?
    var start: Date?
    var end: Date?
    var focusConfidence: Double?
    var pomodoroSegments: [PomodoroSegment]

    init(
        id: UUID = UUID(),
        task: TaskItem?,
        start: Date? = nil,
        end: Date? = nil,
        focusConfidence: Double? = nil,
        pomodoroSegments: [PomodoroSegment]
    ) {
        self.id = id
        self.task = task
        self.start = start
        self.end = end
        self.focusConfidence = focusConfidence
        self.pomodoroSegments = pomodoroSegments
    }

    var totalDurationMinutes: Int {
        pomodoroSegments.map(\.durationMinutes).reduce(0, +)
    }

    var focusDurationMinutes: Int {
        pomodoroSegments
            .filter { $0.phase == .focus }
            .map(\.durationMinutes)
            .reduce(0, +)
    }

    var hasAssignedTime: Bool {
        start != nil && end != nil
    }
}
