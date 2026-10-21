import Foundation

final class ScheduleOptimizer {
    struct Parameters: Codable {
        var focusWeight: Double
        var interruptionPenalty: Double
        var rewardLearningRate: Double
        var explorationRate: Double
    }

    private let pomodoroEngine = AdaptivePomodoroEngine()
    private let initialParameters: Parameters
    private var parameters: Parameters
    private var historicalSessions: [FocusSessionResult] = []

    init(parameters: Parameters = .init(focusWeight: 0.65, interruptionPenalty: 0.3, rewardLearningRate: 0.1, explorationRate: 0.15)) {
        self.initialParameters = parameters
        self.parameters = parameters
    }

    func generateSchedule(tasks: [TaskItem], preferredStart: Date) -> [ScheduleBlock] {
        generateSchedule(tasks: tasks)
    }

    func generateSchedule(tasks: [TaskItem]) -> [ScheduleBlock] {
        let focusTasks = tasks.filter(\.requiresFocus)
        guard !focusTasks.isEmpty else { return [] }

        var blocks: [ScheduleBlock] = []

        for task in prioritize(tasks: focusTasks) {
            let pomodoroPlan = pomodoroEngine.buildPlan(for: task, attentionBaseline: averageAttention())
            let block = ScheduleBlock(
                task: task,
                focusConfidence: evidenceScore(for: task),
                pomodoroSegments: pomodoroPlan
            )
            blocks.append(block)
        }
        return blocks
    }

    func update(with session: FocusSessionResult) {
        apply(session: session)
    }

    func restore(with sessions: [FocusSessionResult]) {
        historicalSessions.removeAll(keepingCapacity: true)
        parameters = initialParameters
        for session in sessions.suffix(60) {
            apply(session: session)
        }
    }

    func averageAttention() -> Double {
        guard !historicalSessions.isEmpty else { return 0.65 }
        return historicalSessions.map(\.averageAttention).reduce(0, +) / Double(historicalSessions.count)
    }

    private func prioritize(tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let lhsScore = score(for: lhs)
            let rhsScore = score(for: rhs)
            return lhsScore > rhsScore
        }
    }

    private func score(for task: TaskItem) -> Double {
        let urgencyBoost: Double
        switch task.urgency {
        case .urgent: urgencyBoost = 0.35
        case .upcoming: urgencyBoost = 0.2
        case .flexible: urgencyBoost = 0.05
        }

        let deadlineBoost: Double
        if let deadline = task.deadline {
            let hoursUntilDeadline = deadline.timeIntervalSinceNow / 3600
            switch hoursUntilDeadline {
            case ..<0: deadlineBoost = 0.35
            case ..<6: deadlineBoost = 0.3
            case ..<24: deadlineBoost = 0.2
            case ..<72: deadlineBoost = 0.1
            default: deadlineBoost = 0.03
            }
        } else {
            deadlineBoost = 0
        }

        let sourceBoost: Double
        switch task.source {
        case .email: sourceBoost = 0.05
        case .calendar: sourceBoost = 0.04
        case .manual: sourceBoost = 0.02
        }

        let tieBreaker = deterministicTieBreaker(for: task.id)
        return task.priority.weight + urgencyBoost + task.focusScore * parameters.focusWeight + deadlineBoost + sourceBoost + tieBreaker
    }

    private func evidenceScore(for task: TaskItem) -> Double? {
        let sessions = historicalSessions.filter { $0.taskId == task.id }
        guard !sessions.isEmpty else { return nil }

        let attention = sessions.map(\.averageAttention).average
        let adherence = sessions.map(\.adherence).average.clamped(to: 0...1)
        let interruptions = sessions.map { Double($0.interruptions) }.average
        let interruptionScore = max(0, 1 - min(1, interruptions / 3))
        return (attention * 0.5) + (adherence * 0.35) + (interruptionScore * 0.15)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0.05, value))
    }

    private func apply(session: FocusSessionResult) {
        historicalSessions.append(session)
        if historicalSessions.count > 60 {
            historicalSessions.removeFirst()
        }
        let reward = (session.averageAttention * parameters.focusWeight) - (Double(session.interruptions) * parameters.interruptionPenalty)
        parameters.focusWeight = clamp(parameters.focusWeight + reward * parameters.rewardLearningRate)
        parameters.interruptionPenalty = clamp(parameters.interruptionPenalty - session.adherence * 0.05)
        pomodoroEngine.adapt(using: session)
    }

    private func deterministicTieBreaker(for id: UUID) -> Double {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let checksum = bytes.reduce(0) { $0 + Int($1) } % 100
        return (Double(checksum) / 100.0) * parameters.explorationRate * 0.1
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
