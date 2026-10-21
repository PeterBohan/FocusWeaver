import Foundation

struct ReportGenerator {
    func generate(metrics: [FocusMetric], tasks: [TaskItem], sessions: [FocusSessionResult], completedTasksToday: Int = 0) -> String {
        let calendar = Calendar.current
        let todayMetrics = metrics.filter { calendar.isDateInToday($0.timestamp) }
        let reportMetrics = todayMetrics.isEmpty ? metrics : todayMetrics
        let trackedTasks = tasks.filter { task in
            if !task.isCompleted { return true }
            guard let completedAt = task.completedAt else { return true }
            return calendar.isDateInToday(completedAt)
        }
        let completedTasks = trackedTasks.filter(\.isCompleted)
        let todaySessions = sessions.filter { session in
            guard let date = session.endedAt ?? session.startedAt else { return false }
            return calendar.isDateInToday(date)
        }

        let attention = reportMetrics.map(\.attentionScore).average
        let blink = reportMetrics.map(\.blinkRate).average
        let completionRate = Double(completedTasks.count + completedTasksToday) / Double(max(trackedTasks.count + completedTasksToday, 1))
        let interruptions = todaySessions.map(\.interruptions).reduce(0, +)

        var report = "FocusWeaver Daily Report\n"
        report += "Average attention: \(attention.percentString)\n"
        report += "Average blink rate: \(String(format: "%.2f", blink * 10))/min\n"
        report += "Task completion: \(completionRate.percentString)\n"
        report += "Interruptions detected: \(interruptions)\n"

        if attention < 0.55 {
            report += "Tip: Shorten sessions and add micro-breaks during deep work.\n"
        } else if attention > 0.8 {
            report += "Tip: Try extending focus blocks to capture the high momentum.\n"
        }

        if completionRate < 0.5 {
            report += "Plan: Start with the Do Now quadrant to regain momentum.\n"
        }
        return report
    }
}
