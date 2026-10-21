import SwiftUI

struct FocusSessionView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                if hasFocusTasks {
                    CameraPreviewView(session: viewModel.focusManager.session)
                        .frame(minWidth: 420, minHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topLeading) { permissionBanner }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No timed tasks")
                            .font(.title3.bold())
                        Text("Choose a specific duration in Inbox to use camera focus.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minWidth: 420, minHeight: 320)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.selectedTask?.title ?? "Select a task")
                        .font(.title2.weight(.semibold))
                    CountdownView(remainingSeconds: viewModel.remainingSeconds, segment: viewModel.currentSegment)
                    if viewModel.cameraHoldActive {
                        Label("Timer paused - step back into frame", systemImage: "video.slash")
                            .font(.footnote)
                            .padding(8)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    AttentionSparkline(metrics: viewModel.metrics.suffix(60))
                        .frame(height: 120)
                    FocusMetricGrid(metric: viewModel.focusManager.latestMetric)
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.toggleFocusSession) {
                    Label(viewModel.isFocusSessionActive ? "End Session" : "Start Session", systemImage: viewModel.isFocusSessionActive ? "stop.fill" : "play.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isFocusSessionActive && !(viewModel.selectedTask?.requiresFocus ?? false))

                Picker("Task", selection: $viewModel.selectedTask) {
                    ForEach(viewModel.tasks.filter { !$0.isCompleted && $0.requiresFocus }) { task in
                        Text(task.title).tag(task as TaskItem?)
                    }
                }
                .frame(maxWidth: 260)
                .disabled(viewModel.isFocusSessionActive)

                if !viewModel.tasks.contains(where: { !$0.isCompleted && $0.requiresFocus }) {
                    Text("Add a task with a specific duration to start a camera focus session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if viewModel.focusManager.permissionDenied {
            Label("Camera permission needed", systemImage: "exclamationmark.triangle")
                .padding(8)
                .background(Color.black.opacity(0.6))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
        }
    }

    private var hasFocusTasks: Bool {
        viewModel.tasks.contains { !$0.isCompleted && $0.requiresFocus }
    }
}

private struct CountdownView: View {
    let remainingSeconds: Int
    let segment: PomodoroSegment?

    var body: some View {
        VStack(alignment: .leading) {
            Text(segment?.phase.label ?? "Idle")
                .font(.headline)
            Text(timeString)
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Segment length: \(segment?.durationMinutes ?? 0)m")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeString: String {
        guard remainingSeconds > 0 else { return "00:00" }
        return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

private struct FocusMetricGrid: View {
    let metric: FocusMetric?

    var body: some View {
        HStack(spacing: 16) {
            MetricTile(title: "Attention", subtitle: "live", value: metric?.attentionScore.formatted(.percent) ?? "--")
            MetricTile(title: "Blink", subtitle: "per min", value: blink)
            MetricTile(title: "Posture", subtitle: "variance", value: posture)
        }
    }

    private var blink: String {
        guard let metric else { return "--" }
        return String(format: "%.1f", metric.blinkRate * 10)
    }

    private var posture: String {
        guard let metric else { return "--" }
        return String(format: "%.2f", metric.headPoseVariance)
    }
}

private struct MetricTile: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            Text(value).font(.title.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AttentionSparkline: View {
    let metrics: ArraySlice<FocusMetric>

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(LinearGradient(colors: [.mint, .green], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
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
