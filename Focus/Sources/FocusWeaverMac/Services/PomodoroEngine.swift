import Foundation

final class AdaptivePomodoroEngine {
    struct Configuration {
        var baseFocusMinutes: Int
        var shortBreakMinutes: Int
        var longBreakMinutes: Int
        var cyclesBeforeLongBreak: Int
    }

    private var configuration = Configuration(baseFocusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4)

    func buildPlan(for task: TaskItem, attentionBaseline: Double) -> [PomodoroSegment] {
        let multiplier = attentionBaseline < 0.55 ? 0.8 : (attentionBaseline > 0.75 ? 1.2 : 1.0)
        let focusLength = Int(Double(configuration.baseFocusMinutes) * multiplier)
        guard let estimatedMinutes = task.estimatedMinutes, task.requiresFocus else { return [] }
        let cyclesNeeded = max(1, Int(ceil(Double(estimatedMinutes) / Double(max(focusLength, 15)))))

        var segments: [PomodoroSegment] = []
        var remainingFocusMinutes = estimatedMinutes
        for cycle in 0..<cyclesNeeded {
            let focusDuration = min(remainingFocusMinutes, max(focusLength, 15))
            segments.append(PomodoroSegment(phase: .focus, durationMinutes: focusDuration))
            remainingFocusMinutes -= focusDuration
            guard remainingFocusMinutes > 0 else { break }

            let isLongBreak = (cycle + 1) % configuration.cyclesBeforeLongBreak == 0 || cycle == cyclesNeeded - 1
            let breakPhase: PomodoroPhase = isLongBreak ? .longBreak : .shortBreak
            let breakDuration = breakPhase == .longBreak ? configuration.longBreakMinutes : configuration.shortBreakMinutes
            segments.append(PomodoroSegment(phase: breakPhase, durationMinutes: breakDuration))
        }
        return segments
    }

    func adapt(using sessionResult: FocusSessionResult) {
        let attention = sessionResult.averageAttention
        if attention < 0.5 {
            configuration.baseFocusMinutes = max(15, configuration.baseFocusMinutes - 2)
            configuration.shortBreakMinutes = min(10, configuration.shortBreakMinutes + 1)
        } else if attention > 0.8 {
            configuration.baseFocusMinutes = min(40, configuration.baseFocusMinutes + 2)
        }

        if sessionResult.interruptions > 1 {
            configuration.cyclesBeforeLongBreak = max(2, configuration.cyclesBeforeLongBreak - 1)
        } else {
            configuration.cyclesBeforeLongBreak = min(5, configuration.cyclesBeforeLongBreak + 1)
        }
    }
}
