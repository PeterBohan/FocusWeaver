import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedTask) {
                Section("Today") {
                    ForEach(viewModel.tasks.filter { !$0.isCompleted }) { task in
                        TaskRow(task: task, isSelected: viewModel.selectedTask?.id == task.id) {
                            viewModel.selectedTask = task
                        }
                    }
                }

                if viewModel.tasks.contains(where: \.isCompleted) {
                    Section("Completed") {
                        ForEach(viewModel.tasks.filter(\.isCompleted)) { task in
                            TaskRow(task: task, isSelected: false, action: {})
                                .opacity(0.5)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar { ToolbarItem(placement: .automatic) { Button("Refresh", action: { Task { await viewModel.refreshTasks() } }) } }
        } detail: {
            TabView {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "chart.pie") }
                TaskInboxView()
                    .tabItem { Label("Inbox", systemImage: "tray.full") }
                SchedulerView()
                    .tabItem { Label("Planner", systemImage: "calendar") }
                FocusSessionView()
                    .tabItem { Label("Focus", systemImage: "camera") }
                AnalyticsView()
                    .tabItem { Label("Insights", systemImage: "waveform.path.ecg") }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .fontWeight(.medium)
                    Spacer()
                    Text(task.eisenhowerQuadrant.label)
                        .font(.caption)
                        .padding(4)
                        .background(quadrantColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(task.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var quadrantColor: Color {
        switch task.eisenhowerQuadrant {
        case .doNow: return .red
        case .schedule: return .orange
        case .delegate: return .blue
        case .eliminate: return .gray
        }
    }
}
