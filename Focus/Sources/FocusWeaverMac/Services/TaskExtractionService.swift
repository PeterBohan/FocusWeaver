import Foundation
import EventKit

enum TaskSuggestionPolicy {
    static let maxSuggestionsPerRefresh = 3

    static func isRelevantEmail(subject: String, body: String, sender: String) -> Bool {
        let text = normalizedText([subject, body, sender])
        return hasWorkOrSchoolContext(text) && hasTaskSignal(text) && !isLikelyAdvertisement(text)
    }

    static func isRelevantCalendarEvent(title: String, notes: String, location: String) -> Bool {
        let text = normalizedText([title, notes, location])
        return hasWorkOrSchoolContext(text) && hasCalendarPrepSignal(text) && !hasExcludedPersonalSignal(text)
    }

    static func rankedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            if lhsScore == rhsScore {
                return (lhs.deadline ?? .distantFuture) < (rhs.deadline ?? .distantFuture)
            }
            return lhsScore > rhsScore
        }
    }

    private static func score(_ task: TaskItem) -> Int {
        let text = normalizedText([task.title, task.details])
        var score = 0
        if task.source == .calendar { score += 4 }
        if task.urgency == .urgent { score += 4 }
        if task.priority == .high { score += 3 }
        if containsAny(["action required", "deadline", "due", "submit", "review", "reply", "prepare"], in: text) {
            score += 3
        }
        if hasSchoolContext(text) { score += 2 }
        if hasWorkContext(text) { score += 2 }
        return score
    }

    private static func normalizedText(_ parts: [String]) -> String {
        parts.joined(separator: " ").lowercased()
    }

    private static func hasWorkOrSchoolContext(_ text: String) -> Bool {
        hasWorkContext(text) || hasSchoolContext(text)
    }

    private static func hasWorkContext(_ text: String) -> Bool {
        containsAny([
            "work", "project", "client", "manager", "team", "meeting", "standup",
            "sync", "sprint", "review", "report", "proposal", "contract", "invoice",
            "deadline", "presentation", "slides", "document", "code", "bug",
            "pull request", "deploy", "release", "roadmap", "backlog", "interview",
            "internship", "job", "office", "company", "customer"
        ], in: text)
    }

    private static func hasSchoolContext(_ text: String) -> Bool {
        containsAny([
            "school", "class", "course", "lecture", "seminar", "lab", "homework",
            "assignment", "exam", "quiz", "midterm", "final", "professor", "teacher",
            "instructor", "student", "campus", "college", "university", "syllabus",
            "grade", "capstone"
        ], in: text)
    }

    private static func hasTaskSignal(_ text: String) -> Bool {
        containsAny([
            "action required", "deadline", "urgent", "review", "submit", "reply",
            "respond", "send", "due", "follow up", "follow-up", "complete", "finish",
            "prepare", "prep", "update", "read before", "please"
        ], in: text)
    }

    private static func hasCalendarPrepSignal(_ text: String) -> Bool {
        containsAny([
            "agenda", "prepare", "prep", "review", "demo", "present", "presentation",
            "interview", "client", "decision", "planning", "workshop", "deadline",
            "assignment", "exam", "quiz", "lecture", "seminar", "lab", "office hours",
            "sync", "standup", "1:1", "one-on-one"
        ], in: text)
    }

    private static func isLikelyAdvertisement(_ text: String) -> Bool {
        containsAny([
            "unsubscribe", "sale", "discount", "coupon", "promo", "promotion",
            "limited time", "buy now", "shop now", "free shipping", "sponsored",
            "advertisement", "marketing", "newsletter", "webinar", "upgrade",
            "clearance", "new arrivals", "cart", "order now", "% off", "offer expires"
        ], in: text)
    }

    private static func hasExcludedPersonalSignal(_ text: String) -> Bool {
        containsAny([
            "birthday", "holiday", "ooo", "out of office", "vacation", "lunch",
            "dinner", "workout", "gym", "doctor", "dentist", "haircut", "errand",
            "groceries", "flight", "hotel", "party", "concert", "appointment",
            "unsubscribe", "sale", "discount", "promo", "promotion"
        ], in: text)
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

protocol TaskExtractionService: Sendable {
    func fetchTasks(requestAccessIfNeeded: Bool) async throws -> [TaskItem]
}

extension TaskExtractionService {
    func fetchTasks() async throws -> [TaskItem] {
        try await fetchTasks(requestAccessIfNeeded: true)
    }
}

struct CompositeTaskExtractionService: TaskExtractionService {
    private let extractors: [any TaskExtractionService]

    init(extractors: [any TaskExtractionService]) {
        self.extractors = extractors
    }

    func fetchTasks(requestAccessIfNeeded: Bool) async throws -> [TaskItem] {
        var fetchedTasks: [TaskItem] = []
        for extractor in extractors {
            do {
                fetchedTasks.append(
                    contentsOf: try await extractor.fetchTasks(requestAccessIfNeeded: requestAccessIfNeeded)
                )
            } catch {
                print("Task extractor skipped: \(error.localizedDescription)")
            }
        }
        return TaskSuggestionPolicy.rankedTasks(fetchedTasks)
    }
}

struct EmailTaskExtractor: TaskExtractionService {
    private let messages: [EmailMessage]

    init(messages: [EmailMessage]) {
        self.messages = messages
    }

    func fetchTasks(requestAccessIfNeeded: Bool = true) async throws -> [TaskItem] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return messages.compactMap { parseTask(from: $0) }
    }

    private func parseTask(from message: EmailMessage) -> TaskItem? {
        let body = message.body.lowercased()
        let subject = message.subject.lowercased()
        guard TaskSuggestionPolicy.isRelevantEmail(subject: subject, body: body, sender: message.sender) else {
            return nil
        }

        let estimated = estimateMinutes(from: body)
        let priority: TaskPriority = body.contains("urgent") ? .high : .medium
        let urgency: TaskUrgency = body.contains("friday") || body.contains("asap") || body.contains("tomorrow") ? .urgent : .upcoming

        return TaskItem(
            title: message.subject.replacingOccurrences(of: "FW:", with: "").trimmingCharacters(in: .whitespaces),
            details: emailDetails(from: message),
            estimatedMinutes: estimated,
            priority: priority,
            urgency: urgency,
            source: .email,
            deadline: Calendar.current.date(byAdding: .day, value: 2, to: message.receivedAt)
        )
    }

    private func emailDetails(from message: EmailMessage) -> String {
        var details = String(message.body.prefix(280))
        let sender = message.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sender.isEmpty {
            details = "From: \(sender). \(details)"
        }
        return details
    }

    private func estimateMinutes(from body: String) -> Int {
        if body.contains("report") { return 90 }
        if body.contains("reply") { return 20 }
        if body.contains("slides") || body.contains("presentation") { return 60 }
        return 45
    }
}

struct CalendarTaskExtractor: TaskExtractionService {
    private let events: [CalendarEvent]

    init(events: [CalendarEvent]) {
        self.events = events
    }

    func fetchTasks(requestAccessIfNeeded: Bool = true) async throws -> [TaskItem] {
        try await Task.sleep(nanoseconds: 80_000_000)
        return events.filter { $0.requiresPreparation }.map { event in
            TaskItem(
                title: "Prep: \(event.title)",
                details: event.notes,
                estimatedMinutes: event.preparationMinutes,
                priority: event.importance,
                urgency: event.startDate.timeIntervalSinceNow < 36_000 ? .urgent : .upcoming,
                source: .calendar,
                deadline: event.startDate
            )
        }
    }
}

struct AppleMailTaskExtractor: TaskExtractionService {
    private let messageLimit: Int

    init(messageLimit: Int = 40) {
        self.messageLimit = messageLimit
    }

    func fetchTasks(requestAccessIfNeeded: Bool) async throws -> [TaskItem] {
        guard requestAccessIfNeeded else { return [] }
        let limit = messageLimit
        let messages = try await Task.detached(priority: .utility) {
            try loadMessages(messageLimit: limit)
        }.value
        return try await EmailTaskExtractor(messages: messages).fetchTasks(requestAccessIfNeeded: requestAccessIfNeeded)
    }
}

struct AppleCalendarTaskExtractor: TaskExtractionService {
    private let lookAheadDays: Int
    private let eventLimit: Int

    init(lookAheadDays: Int = 14, eventLimit: Int = 40) {
        self.lookAheadDays = lookAheadDays
        self.eventLimit = eventLimit
    }

    func fetchTasks(requestAccessIfNeeded: Bool) async throws -> [TaskItem] {
        let eventStore = EKEventStore()
        let hasAccess = try await hasCalendarAccess(eventStore: eventStore, requestAccessIfNeeded: requestAccessIfNeeded)
        guard hasAccess else { return [] }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(eventLimit)
            .compactMap { calendarEvent(from: $0, now: now) }

        return try await CalendarTaskExtractor(events: Array(events)).fetchTasks(requestAccessIfNeeded: requestAccessIfNeeded)
    }

    private func hasCalendarAccess(eventStore: EKEventStore, requestAccessIfNeeded: Bool) async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:
                return true
            case .notDetermined where requestAccessIfNeeded:
                return try await eventStore.requestFullAccessToEvents()
            case .authorized:
                return true
            default:
                return false
            }
        } else {
            switch status {
            case .authorized:
                return true
            case .notDetermined where requestAccessIfNeeded:
                return try await requestLegacyEventAccess(eventStore: eventStore)
            default:
                return false
            }
        }
    }

    private func requestLegacyEventAccess(eventStore: EKEventStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func calendarEvent(from event: EKEvent, now: Date) -> CalendarEvent? {
        guard event.endDate > now, !event.isAllDay else { return nil }

        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchableText = "\(title) \(notes) \(location)".lowercased()
        guard TaskSuggestionPolicy.isRelevantCalendarEvent(title: title, notes: notes, location: location) else { return nil }

        let durationMinutes = max(10, Int(event.endDate.timeIntervalSince(event.startDate) / 60))

        return CalendarEvent(
            title: title,
            startDate: event.startDate,
            notes: details(for: event, notes: notes, location: location),
            requiresPreparation: true,
            preparationMinutes: preparationMinutes(for: searchableText, durationMinutes: durationMinutes),
            importance: priority(for: searchableText, startDate: event.startDate)
        )
    }

    private func details(for event: EKEvent, notes: String, location: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var details = "Starts \(formatter.string(from: event.startDate))."
        if !location.isEmpty {
            details += " Location: \(location)."
        }
        if !notes.isEmpty {
            details += " Notes: \(String(notes.prefix(220)))"
        }
        return details
    }

    private func preparationMinutes(for text: String, durationMinutes: Int) -> Int {
        if text.contains("presentation") || text.contains("present") || text.contains("demo") { return 60 }
        if text.contains("interview") || text.contains("client") || text.contains("review") { return 45 }
        if text.contains("planning") || text.contains("workshop") { return 40 }
        if durationMinutes >= 60 { return 35 }
        return 25
    }

    private func priority(for text: String, startDate: Date) -> TaskPriority {
        if startDate.timeIntervalSinceNow < 24 * 60 * 60 { return .high }
        if text.contains("urgent") || text.contains("deadline") || text.contains("interview") || text.contains("client") {
            return .high
        }
        if text.contains("standup") || text.contains("sync") { return .low }
        return .medium
    }
}

struct CalendarEvent: Identifiable, Sendable {
    let id: UUID
    let title: String
    let startDate: Date
    let notes: String
    let requiresPreparation: Bool
    let preparationMinutes: Int
    let importance: TaskPriority

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        notes: String,
        requiresPreparation: Bool = true,
        preparationMinutes: Int = 30,
        importance: TaskPriority = .medium
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.notes = notes
        self.requiresPreparation = requiresPreparation
        self.preparationMinutes = preparationMinutes
        self.importance = importance
    }
}

private enum AppleMailExtractionError: LocalizedError {
    case scriptCreationFailed
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Apple Mail task extraction script could not be created."
        case .scriptFailed(let message):
            return message
        }
    }
}

private func loadMessages(messageLimit: Int) throws -> [EmailMessage] {
    let rowSeparator = String(UnicodeScalar(30)!)
    let fieldSeparator = String(UnicodeScalar(31)!)
    let scriptSource = """
    use scripting additions

    on cleanedText(rawValue)
        set oldDelimiters to AppleScript's text item delimiters
        set rawText to rawValue as text
        repeat with delimiterValue in {ASCII character 30, ASCII character 31, return, linefeed, tab}
            set AppleScript's text item delimiters to delimiterValue
            set textParts to text items of rawText
            set AppleScript's text item delimiters to " "
            set rawText to textParts as text
        end repeat
        set AppleScript's text item delimiters to oldDelimiters
        return rawText
    end cleanedText

    set rowDelimiter to ASCII character 30
    set fieldDelimiter to ASCII character 31
    set collectedOutput to ""
    set messageLimit to \(max(1, messageLimit))

    tell application id "com.apple.mail"
        set inboxMessages to messages of inbox
        set messageTotal to count of inboxMessages
        if messageTotal is 0 then return ""
        if messageTotal < messageLimit then set messageLimit to messageTotal

        repeat with messageIndex from 1 to messageLimit
            set currentMessage to item messageIndex of inboxMessages
            set subjectText to my cleanedText(subject of currentMessage)
            set contentText to my cleanedText(content of currentMessage)
            set senderText to my cleanedText(sender of currentMessage)
            if (length of contentText) > 1200 then set contentText to text 1 thru 1200 of contentText
            set collectedOutput to collectedOutput & subjectText & fieldDelimiter & contentText & fieldDelimiter & senderText & rowDelimiter
        end repeat
    end tell

    return collectedOutput
    """

    guard let script = NSAppleScript(source: scriptSource) else {
        throw AppleMailExtractionError.scriptCreationFailed
    }

    var errorInfo: NSDictionary?
    let output = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Apple Mail task extraction failed."
        throw AppleMailExtractionError.scriptFailed(message)
    }

    guard let rawRows = output.stringValue, !rawRows.isEmpty else { return [] }
    return rawRows
        .split(separator: Character(rowSeparator), omittingEmptySubsequences: true)
        .compactMap { row in
            let fields = row.split(separator: Character(fieldSeparator), omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            let subject = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let sender = fields.count >= 3 ? String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !subject.isEmpty || !body.isEmpty else { return nil }
            return EmailMessage(subject: subject.isEmpty ? "Mail follow-up" : subject, body: body, sender: sender, receivedAt: .now)
        }
}
