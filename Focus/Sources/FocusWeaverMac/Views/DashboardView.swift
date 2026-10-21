import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("FocusWeaver Dashboard")
                    .font(.largeTitle.bold())

                AdaptiveGrid {
                    MetricCard(title: "Attention", value: attentionValue, subtitle: "Live camera + ML score")
                    MetricCard(title: "Tasks Done", value: completionValue, subtitle: "Eisenhower progress")
                    MetricCard(title: "Streak", value: "\(viewModel.productiveDayStreak)d", subtitle: "Consistent days")
                    MetricCard(title: "Avg Blink", value: blinkValue, subtitle: "Lower = better focus")
                }

                SectionHeader("Upcoming Focus Blocks")
                if viewModel.schedule.isEmpty {
                    Text("No focus blocks yet. Add a task with a specific duration from Inbox to generate a plan.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.schedule.prefix(3)) { block in
                            ScheduleBlockRow(block: block)
                        }
                    }
                }

                SectionHeader("Daily Report")
                VStack(alignment: .leading, spacing: 12) {
                    ReportActionsRow(report: viewModel.dailyReport)
                    Text(viewModel.dailyReport.isEmpty ? "Run at least one focus session to generate insights." : viewModel.dailyReport)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
    }

    private var attentionValue: String {
        guard let score = viewModel.dashboardAttentionScore else { return "--" }
        return score.formatted(.percent.precision(.fractionLength(0)))
    }

    private var blinkValue: String {
        guard let blinkRate = viewModel.dashboardBlinkRate else { return "--" }
        return String(format: "%.1f", blinkRate * 10) + "/m"
    }

    private var completionValue: String {
        "\(viewModel.dashboardCompletedTasksCount)/\(viewModel.dashboardTrackedTasksCount)"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(value).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minHeight: 140, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdaptiveGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AdaptiveStack(spacing: 16) {
            content
        }
    }
}

private struct AdaptiveStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: spacing, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
    }
}

private struct ScheduleBlockRow: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading) {
                Text(block.task?.title ?? "Focus Block")
                    .font(.headline)
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let confidence = block.focusConfidence {
                    Text("Based on prior sessions")
                        .font(.caption)
                    ProgressView(value: confidence)
                        .frame(width: 120)
                } else {
                    Text("No prior session data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dateRange: String {
        guard let start = block.start, let end = block.end else {
            return "Unscheduled · \(block.focusDurationMinutes)m focus"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}

private struct ReportActionsRow: View {
    let report: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: copyReport) {
                Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(report.isEmpty)

            ShareLink(item: report) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(report.isEmpty)

            Spacer()
        }
    }

    private func copyReport() {
        guard !report.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                copied = false
            }
        }
    }
}
