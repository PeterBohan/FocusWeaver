import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Focus Analytics")
                    .font(.largeTitle.bold())

                FocusTrendChart(metrics: Array(viewModel.metrics.suffix(120)))
                    .frame(height: 220)

                QuadrantBreakdown(tasks: viewModel.tasks)

                SessionHistorySection(sessions: viewModel.sessionHistory, tasks: viewModel.tasks)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw metrics")
                        .font(.headline)
                    if viewModel.metrics.isEmpty {
                        Text("Start a session to collect metrics")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.metrics.suffix(5)) { metric in
                            FocusMetricRow(metric: metric)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct FocusTrendChart: View {
    let metrics: [FocusMetric]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Attention trend")
                .font(.headline)
            GeometryReader { proxy in
                let points = normalizedPoints(in: proxy.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.accentColor.opacity(0.05))
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !metrics.isEmpty else { return [] }
        let values = metrics.map(\.attentionScore)
        let maxValue = max(values.max() ?? 1, 0.01)
        let minValue = min(values.min() ?? 0, 0)
        let range = max(0.01, maxValue - minValue)
        return values.enumerated().map { index, value in
            let x = size.width * Double(index) / Double(max(metrics.count - 1, 1))
            let normalized = (value - minValue) / range
            let y = size.height - normalized * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

private struct QuadrantBreakdown: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eisenhower distribution")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(TaskQuadrant.allCases, id: \.self) { quadrant in
                    let count = tasks.filter { $0.eisenhowerQuadrant == quadrant }.count
                    VStack(alignment: .leading) {
                        Text(quadrant.label)
                            .font(.headline)
                        Text("\(count) tasks")
                            .font(.title2.bold())
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(color(for: quadrant).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func color(for quadrant: TaskQuadrant) -> Color {
        switch quadrant {
        case .doNow: return .red
        case .schedule: return .orange
        case .delegate: return .blue
        case .eliminate: return .gray
        }
    }
}

private struct FocusMetricRow: View {
    let metric: FocusMetric

    var body: some View {
        HStack {
            Text(metric.timestamp, style: .time)
                .frame(width: 80, alignment: .leading)
            ProgressView(value: metric.attentionScore)
                .frame(width: 160)
            Text(metric.attentionScore.formatted(.percent))
                .frame(width: 70, alignment: .trailing)
            Text("Blink: \(String(format: "%.1f", metric.blinkRate * 10))/m")
                .frame(width: 140, alignment: .leading)
        }
        .font(.caption)
    }
}

private struct SessionHistorySection: View {
    let sessions: [FocusSessionResult]
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent focus sessions")
                .font(.headline)

            if sessions.isEmpty {
                Text("Run a focus block to start tracking history.")
                    .foregroundStyle(.secondary)
            } else {
                let recent = Array(sessions.suffix(6).reversed())
                ForEach(recent) { session in
                    SessionHistoryRow(session: session, title: title(for: session))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func title(for session: FocusSessionResult) -> String {
        guard let id = session.taskId,
              let task = tasks.first(where: { $0.id == id }) else {
            return "Ad-hoc focus block"
        }
        return task.title
    }
}

private struct SessionHistoryRow: View {
    let session: FocusSessionResult
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("Completed \(session.completedMinutes)m of \(session.plannedMinutes)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.averageAttention.formatted(.percent))
                    .font(.headline)
                Text(emoji)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text("Interruptions")
                    .font(.caption2)
                Text("\(session.interruptions)")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emoji: String {
        switch session.averageAttention {
        case ..<0.5: return "🟠"
        case 0.5..<0.75: return "🟡"
        default: return "🟢"
        }
    }
}
