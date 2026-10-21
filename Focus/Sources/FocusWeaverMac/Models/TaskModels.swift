import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: String { rawValue }
    var weight: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.6
        case .low: return 0.3
        }
    }
}

enum TaskUrgency: String, Codable, CaseIterable, Sendable {
    case urgent
    case upcoming
    case flexible
}

enum TaskQuadrant: String, Codable, CaseIterable, Sendable {
    case doNow
    case schedule
    case delegate
    case eliminate

    static func quadrant(priority: TaskPriority, urgency: TaskUrgency) -> TaskQuadrant {
        switch (priority, urgency) {
        case (.high, .urgent): return .doNow
        case (.high, _), (.medium, .urgent): return .schedule
        case (.medium, _): return .delegate
        default: return .eliminate
        }
    }

    var label: String {
        switch self {
        case .doNow: return "Do Now"
        case .schedule: return "Schedule"
        case .delegate: return "Delegate"
        case .eliminate: return "Eliminate"
        }
    }
}

enum TaskSource: String, Codable, CaseIterable, Sendable {
    case email
    case calendar
    case manual

    var label: String {
        switch self {
        case .email: return "Email"
        case .calendar: return "Calendar"
        case .manual: return "Manual"
        }
    }

    var icon: String {
        switch self {
        case .email: return "envelope"
        case .calendar: return "calendar"
        case .manual: return "person.fill.checkmark"
        }
    }
}

enum TaskDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case allDay
    case timed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "No duration"
        case .allDay: return "All day"
        case .timed: return "Specific duration"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var details: String
    var estimatedMinutes: Int?
    var duration: TaskDuration
    var priority: TaskPriority
    var urgency: TaskUrgency
    var source: TaskSource
    var deadline: Date?
    var isCompleted: Bool
    var createdAt: Date?
    var completedAt: Date?
    var focusScore: Double
    var recommendedSlot: DateInterval?

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        estimatedMinutes: Int? = nil,
        duration: TaskDuration? = nil,
        priority: TaskPriority,
        urgency: TaskUrgency,
        source: TaskSource,
        deadline: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date? = .now,
        completedAt: Date? = nil,
        focusScore: Double = 0.5,
        recommendedSlot: DateInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        let resolvedDuration = duration ?? (estimatedMinutes == nil ? .none : .timed)
        self.duration = resolvedDuration
        self.estimatedMinutes = resolvedDuration == .timed ? estimatedMinutes.map { max(1, $0) } : nil
        self.priority = priority
        self.urgency = urgency
        self.source = source
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.focusScore = focusScore
        self.recommendedSlot = recommendedSlot
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, details, estimatedMinutes, duration, priority, urgency, source, deadline
        case isCompleted, createdAt, completedAt, focusScore, recommendedSlot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decode(String.self, forKey: .details)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        urgency = try container.decode(TaskUrgency.self, forKey: .urgency)
        source = try container.decode(TaskSource.self, forKey: .source)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        focusScore = try container.decode(Double.self, forKey: .focusScore)
        recommendedSlot = try container.decodeIfPresent(DateInterval.self, forKey: .recommendedSlot)

        let storedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        if let storedDuration = try container.decodeIfPresent(TaskDuration.self, forKey: .duration) {
            duration = storedDuration
            estimatedMinutes = storedDuration == .timed ? (storedMinutes ?? 25) : nil
        } else {
            // Tasks saved before duration became optional were all timed tasks.
            duration = storedMinutes == nil ? .none : .timed
            estimatedMinutes = storedMinutes
        }
        if duration == .timed, let estimatedMinutes {
            self.estimatedMinutes = max(1, estimatedMinutes)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(details, forKey: .details)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encode(duration, forKey: .duration)
        try container.encode(priority, forKey: .priority)
        try container.encode(urgency, forKey: .urgency)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(focusScore, forKey: .focusScore)
        try container.encodeIfPresent(recommendedSlot, forKey: .recommendedSlot)
    }

    var requiresFocus: Bool {
        duration == .timed && estimatedMinutes != nil
    }

    var durationLabel: String {
        switch duration {
        case .none, .allDay:
            return duration.label
        case .timed:
            guard let estimatedMinutes else { return duration.label }
            return "\(estimatedMinutes) min"
        }
    }

    var eisenhowerQuadrant: TaskQuadrant {
        TaskQuadrant.quadrant(priority: priority, urgency: urgency)
    }
}

struct EmailMessage: Identifiable, Sendable {
    let id: UUID
    let subject: String
    let body: String
    let sender: String
    let receivedAt: Date

    init(id: UUID = UUID(), subject: String, body: String, sender: String = "", receivedAt: Date = .now) {
        self.id = id
        self.subject = subject
        self.body = body
        self.sender = sender
        self.receivedAt = receivedAt
    }
}
