import SwiftUI

struct SchedulerView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel
    @State private var layoutMode: LayoutMode = .list
    private let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Text("Adaptive Planner")
                    .font(.largeTitle.bold())
                Spacer()
                Picker("Layout", selection: $layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                Button(action: { Task { await viewModel.refreshTasks() } }) {
                    Label("Sync", systemImage: "arrow.clockwise")
                }
            }

            if viewModel.schedule.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No focus blocks scheduled")
                        .font(.title3.bold())
                    Text("Add a task with a specific duration from the Inbox to see adaptive recommendations here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch layoutMode {
                case .list:
                    listView
                case .timeline:
                    if viewModel.schedule.allSatisfy({ $0.hasAssignedTime }) {
                        timelineView
                    } else {
                        sequenceView
                    }
                }
            }
        }
        .padding(24)
    }

    private var listView: some View {
        List {
            ForEach(viewModel.schedule) { block in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.task?.title ?? "Focus Block")
                                .font(.headline)
                            Text(timeLabel(for: block))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        FocusConfidenceBadge(symbol: viewModel.focusConfidenceColor(for: block))
                    }

                    Text(viewModel.focusConfidenceLabel(for: block))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(block.pomodoroSegments) { segment in
                                PomodoroChip(segment: segment)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Focus now") {
                            viewModel.startSession(for: block.task)
                        }
                        .disabled(block.task == nil)

                        Button("Complete") {
                            if let task = block.task {
                                viewModel.markTaskComplete(task)
                            }
                        }
                        .disabled(block.task?.isCompleted ?? true)

                        Spacer()

                        Button("Set as next") {
                            if let task = block.task {
                                viewModel.selectedTask = task
                            }
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var sequenceView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested sequence")
                .font(.title2.bold())
            Text("These blocks are ordered by priority. No clock times have been assigned.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            listView
        }
    }

    private func timeLabel(for block: ScheduleBlock) -> String {
        guard let start = block.start, let end = block.end else {
            return "Unscheduled · \(block.focusDurationMinutes)m focus"
        }
        return intervalFormatter.string(from: start, to: end)
    }

    private var timelineView: some View {
        let schedule = viewModel.schedule
        let baseline = schedule.compactMap(\.start).first ?? Date()
        let latest = schedule.compactMap(\.end).last ?? baseline.addingTimeInterval(3600)
        let totalSpan = max(60, latest.timeIntervalSince(baseline))
        let canvasWidth = max(720, CGFloat(totalSpan / 60) * 80)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.title2.bold())
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    ForEach(schedule) { block in
                        if let start = block.start, let end = block.end {
                            let startOffset = CGFloat(start.timeIntervalSince(baseline) / totalSpan) * canvasWidth
                            let blockWidth = max(140, CGFloat(end.timeIntervalSince(start) / totalSpan) * canvasWidth)
                            TimelineBlockCard(
                                block: block,
                                formatter: intervalFormatter,
                                color: color(for: block)
                            )
                            .frame(width: blockWidth)
                            .offset(x: startOffset)
                        }
                    }
                }
                .frame(width: canvasWidth, height: 260, alignment: .topLeading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text("Block width represents duration; position reflects an assigned time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for block: ScheduleBlock) -> Color {
        guard let quadrant = block.task?.eisenhowerQuadrant else {
            return .mint
        }
        switch quadrant {
        case .doNow: return .red
        case .schedule: return .orange
        case .delegate: return .blue
        case .eliminate: return .gray
        }
    }
}

private enum LayoutMode: String, CaseIterable, Identifiable {
    case list
    case timeline

    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return "List"
        case .timeline: return "Timeline"
        }
    }
}

private struct PomodoroChip: View {
    let segment: PomodoroSegment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(segment.durationMinutes)m")
        }
        .font(.caption.bold())
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }

    private var icon: String {
        switch segment.phase {
        case .focus: return "timer"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "bed.double"
        }
    }

    private var color: Color {
        switch segment.phase {
        case .focus: return .green
        case .shortBreak: return .blue
        case .longBreak: return .purple
        }
    }
}

private struct FocusConfidenceBadge: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.title3)
            .accessibilityLabel("Confidence \(symbol)")
    }
}

private struct TimelineBlockCard: View {
    let block: ScheduleBlock
    let formatter: DateIntervalFormatter
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.task?.title ?? "Focus Block")
                .font(.headline)
                .lineLimit(1)
            if let start = block.start, let end = block.end {
                Text(formatter.string(from: start, to: end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unscheduled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let confidence = block.focusConfidence {
                ProgressView(value: confidence) {
                    Text("Based on prior sessions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No prior session data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.35))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.8), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
