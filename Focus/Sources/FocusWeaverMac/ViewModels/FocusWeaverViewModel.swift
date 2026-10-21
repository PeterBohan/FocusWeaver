import Foundation
import Combine
import CryptoKit

@MainActor
final class FocusWeaverViewModel: ObservableObject {
    // Published state
    @Published var tasks: [TaskItem] = []
    @Published var schedule: [ScheduleBlock] = []
    @Published var metrics: [FocusMetric] = []
    @Published var isFocusSessionActive = false
    @Published var remainingSeconds: Int = 0
    @Published var currentSegment: PomodoroSegment?
    @Published var selectedTask: TaskItem?
    @Published var profile: UserProductivityProfile = .baseline
    @Published var dailyReport: String = ""
    @Published private(set) var sessionHistory: [FocusSessionResult] = []
    @Published var cameraHoldActive = false
    @Published private(set) var isRefreshingTaskSuggestions = false
    @Published private(set) var taskSuggestionMessage: String?

    // Services
    let focusManager = FocusDetectionManager()
    private let optimizer = ScheduleOptimizer()
    private let dataStore = FocusDataStore()
    private let reportGenerator = ReportGenerator()
    private let taskStore: TaskDataStore
    private let sessionStore: SessionDataStore
    private let taskExtractor: any TaskExtractionService

    // Session state
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var sessionStartDate: Date?
    private var sessionFocusSamples: [FocusMetric] = []
    private var sessionInterruptions: Int { focusManager.latestMetric?.distractionsDetected ?? 0 }
    private var cameraHoldStart: Date?
    private var cameraHoldTimeoutTask: Task<Void, Never>?
    private var dismissedTaskKeys: Set<String> = []
    private var taskCompletions: [UUID: TaskCompletionRecord] = [:]

    init(taskExtractor: (any TaskExtractionService)? = nil, taskStore: TaskDataStore = TaskDataStore(), sessionStore: SessionDataStore = SessionDataStore()) {
        self.taskStore = taskStore
        self.sessionStore = sessionStore
        self.taskExtractor = taskExtractor ?? CompositeTaskExtractionService(extractors: [
            AppleMailTaskExtractor(),
            AppleCalendarTaskExtractor()
        ])
        if let restoredState = sessionStore.load() {
            profile = restoredState.profile
            sessionHistory = restoredState.sessionHistory
            taskCompletions = restoredState.taskCompletions ?? [:]
        }
        metrics = dataStore.loadMetrics()
        tasks = taskStore.loadTasks() ?? []
        dismissedTaskKeys = taskStore.loadDismissedTaskKeys()
        // Migrate completed tasks to metadata before removing their stored contents.
        for task in tasks where task.isCompleted {
            taskCompletions[task.id] = TaskCompletionRecord(
                completedAt: task.completedAt ?? Date(),
                suggestionKey: task.title.completionSuggestionKey
            )
        }
        persistSessionState()
        tasks.removeAll { $0.isCompleted || taskCompletions[$0.id] != nil }
        taskStore.persist(tasks)
        selectedTask = tasks.first { !$0.isCompleted && $0.requiresFocus }
            ?? tasks.first { !$0.isCompleted }
            ?? tasks.first
        optimizer.restore(with: sessionHistory)
        updateProfileFromUsage()
        persistSessionState()
        bindPersistence()
        bindFocusPipeline()
        Task { await refreshTaskSuggestions(requestAccessIfNeeded: false) }
        rebuildSchedule()
        regenerateReport()
    }

    func toggleFocusSession() {
        isFocusSessionActive ? endSession(saveResult: true) : startSession()
    }

    func startSession(for task: TaskItem? = nil) {
        guard !isFocusSessionActive else { return }
        let candidate = task ?? selectedTask ?? tasks.first(where: \.requiresFocus)
        guard let candidate, candidate.requiresFocus else { return }
        selectedTask = candidate
        sessionFocusSamples.removeAll()
        currentSegment = nil
        focusManager.resetCounters()
        focusManager.start()
        cameraHoldActive = false
        cameraHoldStart = nil
        cameraHoldTimeoutTask?.cancel()
        cameraHoldTimeoutTask = nil
        sessionStartDate = Date()
        isFocusSessionActive = true
        startNextSegment(forceFocus: true)
    }

    func endSession(saveResult: Bool) {
        timer?.invalidate()
        timer = nil
        focusManager.stop()
        defer {
            isFocusSessionActive = false
            sessionStartDate = nil
            cameraHoldActive = false
            cameraHoldStart = nil
            cameraHoldTimeoutTask?.cancel()
            cameraHoldTimeoutTask = nil
        }

        guard saveResult, let startDate = sessionStartDate else { return }
        let endDate = Date()
        let elapsedSeconds = endDate.timeIntervalSince(startDate)
        let elapsedMinutes = max(1, Int(ceil(elapsedSeconds / 60)))
        let attention = sessionFocusSamples.isEmpty
            ? focusManager.latestMetric?.attentionScore ?? profile.averageAttention
            : sessionFocusSamples.map(\.attentionScore).average
        let plannedMinutes = max(
            1,
            selectedBlock()?
                .pomodoroSegments
                .filter { $0.phase == .focus }
                .map(\.durationMinutes)
                .reduce(0, +) ?? currentSegment?.durationMinutes ?? elapsedMinutes
        )
        let result = FocusSessionResult(
            taskId: selectedTask?.id,
            startedAt: startDate,
            endedAt: endDate,
            plannedMinutes: plannedMinutes,
            completedMinutes: elapsedMinutes,
            averageAttention: attention,
            interruptions: sessionInterruptions
        )
        sessionHistory.append(result)
        if sessionHistory.count > 50 {
            sessionHistory.removeFirst()
        }
        optimizer.update(with: result)
        updateProfileFromUsage()
        persistSessionState()
        rebuildSchedule()
        regenerateReport()
    }

    func markTaskComplete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        taskCompletions[task.id] = TaskCompletionRecord(
            completedAt: Date(),
            suggestionKey: tasks[index].title.completionSuggestionKey
        )
        persistSessionState()
        tasks.remove(at: index)
        taskStore.persist(tasks)
        if selectedTask?.id == task.id {
            if isFocusSessionActive {
                endSession(saveResult: true)
            }
            selectedTask = tasks.first { !$0.isCompleted && $0.requiresFocus }
                ?? tasks.first { !$0.isCompleted }
        }
        updateProfileFromUsage()
        persistSessionState()
        rebuildSchedule()
        regenerateReport()
    }

    func refreshTaskSuggestions(requestAccessIfNeeded: Bool = true) async {
        guard !isRefreshingTaskSuggestions else { return }
        isRefreshingTaskSuggestions = true
        if requestAccessIfNeeded {
            taskSuggestionMessage = nil
        }
        defer { isRefreshingTaskSuggestions = false }

        do {
            let existingCount = tasks.count
            let fetched = try await taskExtractor.fetchTasks(requestAccessIfNeeded: requestAccessIfNeeded)
            merge(tasks: fetched, maxAdded: TaskSuggestionPolicy.maxSuggestionsPerRefresh)
            rebuildSchedule()
            regenerateReport()
            let newCount = tasks.count - existingCount
            if requestAccessIfNeeded {
                taskSuggestionMessage = newCount == 0 ? "No new suggestions found." : "Added \(newCount) suggested task\(newCount == 1 ? "" : "s")."
            }
        } catch {
            if requestAccessIfNeeded {
                taskSuggestionMessage = "Could not refresh suggestions."
            }
            print("Task extraction error: \(error.localizedDescription)")
        }
    }

    func refreshTasks() async {
        await refreshTaskSuggestions()
    }

    func regenerateReport() {
        dailyReport = reportGenerator.generate(metrics: metrics, tasks: tasks, sessions: sessionHistory, completedTasksToday: dashboardCompletedTasksCount)
    }

    var dashboardAttentionScore: Double? {
        let todayMetrics = metricsForToday()
        if !todayMetrics.isEmpty {
            return todayMetrics.map(\.attentionScore).average
        }
        return focusManager.latestMetric?.attentionScore
    }

    var dashboardBlinkRate: Double? {
        let todayMetrics = metricsForToday()
        if !todayMetrics.isEmpty {
            return todayMetrics.map(\.blinkRate).average
        }
        return focusManager.latestMetric?.blinkRate
    }

    var dashboardCompletedTasksCount: Int {
        taskCompletions.values.filter {
            Calendar.current.isDateInToday($0.completedAt)
        }.count
    }

    var dashboardTrackedTasksCount: Int {
        tasks.count + dashboardCompletedTasksCount
    }

    var productiveDayStreak: Int {
        consecutiveProductiveDays()
    }

    func focusConfidenceColor(for block: ScheduleBlock) -> String {
        guard let confidence = block.focusConfidence else { return "—" }
        switch confidence {
        case ..<0.5: return "⚠️"
        case 0.5..<0.75: return "🟡"
        default: return "🟢"
        }
    }

    func focusConfidenceLabel(for block: ScheduleBlock) -> String {
        guard let confidence = block.focusConfidence else {
            return "No prior session data"
        }
        return "Based on prior sessions: \(confidence.formatted(.percent))"
    }

    func deleteTask(_ task: TaskItem) {
        dismissedTaskKeys.insert(task.title.normalizedForComparison)
        persistDismissedTaskKeys()
        tasks.removeAll { $0.id == task.id }
        if selectedTask?.id == task.id {
            selectedTask = tasks.first { !$0.isCompleted && $0.requiresFocus }
                ?? tasks.first { !$0.isCompleted }
        }
        taskStore.persist(tasks)
        rebuildSchedule()
        regenerateReport()
    }

    func addManualTask(title: String, details: String, duration: TaskDuration, estimatedMinutes: Int?, priority: TaskPriority, urgency: TaskUrgency) {
        dismissedTaskKeys.remove(title.normalizedForComparison)
        persistDismissedTaskKeys()
        let newTask = TaskItem(
            title: title,
            details: details,
            estimatedMinutes: estimatedMinutes,
            duration: duration,
            priority: priority,
            urgency: urgency,
            source: .manual,
            createdAt: Date()
        )
        tasks.append(newTask)
        selectedTask = newTask
        taskStore.persist(tasks)
        rebuildSchedule()
        regenerateReport()
    }

    // Kept for callers that create a timed task using the older API.
    func addManualTask(title: String, details: String, estimatedMinutes: Int, priority: TaskPriority, urgency: TaskUrgency) {
        addManualTask(
            title: title,
            details: details,
            duration: .timed,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            urgency: urgency
        )
    }

    func update(task: TaskItem, estimatedMinutes: Int?, duration: TaskDuration, priority: TaskPriority, urgency: TaskUrgency) {
        update(
            task: task,
            title: task.title,
            details: task.details,
            estimatedMinutes: estimatedMinutes,
            duration: duration,
            priority: priority,
            urgency: urgency
        )
    }

    // Kept for callers that update a timed task using the older API.
    func update(task: TaskItem, estimatedMinutes: Int, priority: TaskPriority, urgency: TaskUrgency) {
        update(task: task, estimatedMinutes: estimatedMinutes, duration: .timed, priority: priority, urgency: urgency)
    }

    func update(task: TaskItem, title: String, details: String, estimatedMinutes: Int?, duration: TaskDuration, priority: TaskPriority, urgency: TaskUrgency) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[index].title = cleanedTitle.isEmpty ? "Untitled Task" : cleanedTitle
        tasks[index].details = cleanedDetails.isEmpty ? "No details provided." : cleanedDetails
        tasks[index].duration = duration
        tasks[index].estimatedMinutes = duration == .timed ? estimatedMinutes.map { max(10, $0) } : nil
        tasks[index].priority = priority
        tasks[index].urgency = urgency
        if selectedTask?.id == task.id {
            selectedTask = tasks[index]
        }
        taskStore.persist(tasks)
        rebuildSchedule()
        regenerateReport()
    }

    private func startNextSegment(forceFocus: Bool = false) {
        let plan = selectedBlock()?.pomodoroSegments ?? [PomodoroSegment(phase: .focus, durationMinutes: 25)]
        let nextIndex: Int
        if forceFocus {
            nextIndex = plan.firstIndex { $0.phase == .focus } ?? 0
        } else if let current = currentSegment, let index = plan.firstIndex(where: { $0.id == current.id }) {
            let candidate = plan.index(after: index)
            if candidate >= plan.endIndex {
                endSession(saveResult: true)
                return
            }
            nextIndex = candidate
        } else {
            nextIndex = 0
        }
        guard plan.indices.contains(nextIndex) else {
            endSession(saveResult: true)
            return
        }
        currentSegment = plan[nextIndex]
        remainingSeconds = plan[nextIndex].durationMinutes * 60
        startTimer()
    }

    private func selectedBlock() -> ScheduleBlock? {
        guard let task = selectedTask else { return nil }
        return schedule.first { $0.task?.id == task.id }
    }

    private func startTimer() {
        timer?.invalidate()
        guard !cameraHoldActive else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.timer?.invalidate()
                    self.startNextSegment()
                }
            }
        }
    }

    private func bindFocusPipeline() {
        focusManager.$latestMetric
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metric in
                guard let self else { return }
                self.metrics.append(metric)
                self.sessionFocusSamples.append(metric)
                self.metrics = Array(self.metrics.suffix(360))
            }
            .store(in: &cancellables)

        focusManager.$isUserVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                handleCameraVisibilityChange(isVisible: visible)
            }
            .store(in: &cancellables)
    }

    private func bindPersistence() {
        $tasks
            .dropFirst()
            .sink { [weak self] tasks in
                self?.taskStore.persist(tasks)
            }
            .store(in: &cancellables)

        $metrics
            .dropFirst()
            .sink { [weak self] metrics in
                self?.dataStore.persistMetrics(metrics)
            }
            .store(in: &cancellables)

        $profile
            .dropFirst()
            .sink { [weak self] profile in
                guard let self else { return }
                self.sessionStore.persist(profile: profile, sessionHistory: self.sessionHistory, taskCompletions: self.taskCompletions)
            }
            .store(in: &cancellables)

        $sessionHistory
            .dropFirst()
            .sink { [weak self] history in
                guard let self else { return }
                self.sessionStore.persist(profile: self.profile, sessionHistory: history, taskCompletions: self.taskCompletions)
            }
            .store(in: &cancellables)
    }

    private func merge(tasks newTasks: [TaskItem], maxAdded: Int? = nil) {
        var merged = tasks
        var addedCount = 0
        let completedKeys = Set(taskCompletions.values.map(\.suggestionKey))
        for task in newTasks {
            if let maxAdded, addedCount >= maxAdded {
                break
            }
            let normalizedTitle = task.title.normalizedForComparison
            if completedKeys.contains(task.title.completionSuggestionKey) {
                continue
            }
            if dismissedTaskKeys.contains(normalizedTitle) {
                continue
            }
            if merged.contains(where: {
                $0.id == task.id || $0.title.normalizedForComparison == normalizedTitle
            }) {
                continue
            }
            merged.append(task)
            addedCount += 1
        }
        tasks = merged
        if selectedTask == nil {
            selectedTask = tasks.first { !$0.isCompleted && $0.requiresFocus }
                ?? tasks.first { !$0.isCompleted }
                ?? tasks.first
        }
        taskStore.persist(tasks)
    }

    private func rebuildSchedule() {
        schedule = optimizer.generateSchedule(tasks: tasks.filter { !$0.isCompleted })
    }

    private func handleCameraVisibilityChange(isVisible: Bool) {
        guard isFocusSessionActive else { return }
        if isVisible {
            resumeFromCameraHoldIfNeeded()
        } else {
            pauseForCameraHold()
        }
    }

    private func pauseForCameraHold() {
        guard !cameraHoldActive else { return }
        cameraHoldActive = true
        cameraHoldStart = Date()
        timer?.invalidate()
        timer = nil
        scheduleCameraHoldTimeout()
    }

    private func resumeFromCameraHoldIfNeeded() {
        guard cameraHoldActive else { return }
        cameraHoldActive = false
        cameraHoldStart = nil
        cameraHoldTimeoutTask?.cancel()
        cameraHoldTimeoutTask = nil
        startTimer()
    }

    private func scheduleCameraHoldTimeout() {
        cameraHoldTimeoutTask?.cancel()
        cameraHoldTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            await MainActor.run {
                self?.handleCameraHoldTimeout()
            }
        }
    }

    private func handleCameraHoldTimeout() {
        guard cameraHoldActive, isFocusSessionActive else { return }
        endSession(saveResult: false)
    }

    private func persistSessionState() {
        sessionStore.persist(profile: profile, sessionHistory: sessionHistory, taskCompletions: taskCompletions)
    }

    private func updateProfileFromUsage() {
        let recentAttention = metrics.suffix(120).map(\.attentionScore)
        if !recentAttention.isEmpty {
            profile.averageAttention = recentAttention.average
        } else if let latestSession = sessionHistory.last {
            profile.averageAttention = latestSession.averageAttention
        }
        profile.streak = consecutiveProductiveDays()
    }

    private func metricsForToday() -> [FocusMetric] {
        metrics.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private func consecutiveProductiveDays() -> Int {
        let calendar = Calendar.current
        let days = productiveDays(calendar: calendar)
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            guard days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func productiveDays(calendar: Calendar) -> Set<Date> {
        var days = Set(taskCompletions.values.map { calendar.startOfDay(for: $0.completedAt) })
        for session in sessionHistory where session.completedMinutes > 0 {
            if let date = session.endedAt ?? session.startedAt {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        if days.isEmpty, !sessionHistory.isEmpty || tasks.contains(where: \.isCompleted) {
            days.insert(calendar.startOfDay(for: Date()))
        }
        return days
    }

    private func persistDismissedTaskKeys() {
        taskStore.persistDismissedTaskKeys(dismissedTaskKeys)
    }


}

private extension Array where Element == FocusMetric {
    func averageAttention() -> Double {
        guard !isEmpty else { return 0 }
        return map(\.attentionScore).reduce(0, +) / Double(count)
    }
}

private extension String {
    var completionSuggestionKey: String {
        SHA256.hash(data: Data(normalizedForComparison.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    var normalizedForComparison: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
