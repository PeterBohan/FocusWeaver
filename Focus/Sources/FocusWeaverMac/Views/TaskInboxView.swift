import SwiftUI

struct TaskInboxView: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel
    @State private var newTitle = ""
    @State private var newDetails = ""
    @State private var newMinutes = 45
    @State private var newDuration: TaskDuration = .none
    @State private var newPriority: TaskPriority = .medium
    @State private var newUrgency: TaskUrgency = .upcoming

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            quickAddPanel
                .frame(width: 320)

            List {
                ForEach(TaskSource.allCases, id: \.self) { source in
                    Section(header: Label(source.label, systemImage: source.icon)) {
                        let tasks = tasks(for: source)
                        if tasks.isEmpty {
                            Text("No \(source.label.lowercased()) tasks right now.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(tasks) { task in
                                TaskEditorRow(task: task)
                                    .listRowInsets(.init(top: 12, leading: 8, bottom: 12, trailing: 8))
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var quickAddPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick add task")
                .font(.title3.bold())

            Button {
                Task { await viewModel.refreshTaskSuggestions() }
            } label: {
                Label(
                    viewModel.isRefreshingTaskSuggestions ? "Refreshing suggestions" : "Refresh Mail & Calendar",
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRefreshingTaskSuggestions)

            if let message = viewModel.taskSuggestionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $newDetails)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Picker("Duration", selection: $newDuration) {
                ForEach(TaskDuration.allCases) { duration in
                    Text(duration.label).tag(duration)
                }
            }
            .pickerStyle(.menu)

            if newDuration == .timed {
                Stepper(value: $newMinutes, in: 10...240, step: 5) {
                    Text("Specific duration: \(newMinutes) min")
                }
            } else {
                Text(newDuration == .none
                    ? "This task stays in your task list without a camera focus block."
                    : "All-day tasks stay in your task list without a camera focus block.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Priority", selection: $newPriority) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.rawValue.capitalized).tag(priority)
                }
            }
            .pickerStyle(.segmented)

            Picker("Urgency", selection: $newUrgency) {
                ForEach(TaskUrgency.allCases, id: \.self) { urgency in
                    Text(urgencyLabel(urgency)).tag(urgency)
                }
            }
            .pickerStyle(.segmented)

            Button(action: addTask) {
                Label(newDuration == .timed ? "Add to plan" : "Add task", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        viewModel.addManualTask(
            title: title,
            details: newDetails.isEmpty ? "Added via Quick Add" : newDetails,
            duration: newDuration,
            estimatedMinutes: newDuration == .timed ? newMinutes : nil,
            priority: newPriority,
            urgency: newUrgency
        )
        newTitle = ""
        newDetails = ""
        newMinutes = 45
        newDuration = .none
        newPriority = .medium
        newUrgency = .upcoming
    }

    private func tasks(for source: TaskSource) -> [TaskItem] {
        viewModel.tasks.filter { $0.source == source }
    }

    private func urgencyLabel(_ urgency: TaskUrgency) -> String {
        switch urgency {
        case .urgent: return "Now"
        case .upcoming: return "Soon"
        case .flexible: return "Later"
        }
    }
}

private struct TaskEditorRow: View {
    @EnvironmentObject private var viewModel: FocusWeaverViewModel
    let task: TaskItem
    @State private var title: String
    @State private var details: String
    @State private var minutes: Int
    @State private var duration: TaskDuration
    @State private var priority: TaskPriority
    @State private var urgency: TaskUrgency

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _details = State(initialValue: task.details)
        _minutes = State(initialValue: task.estimatedMinutes ?? 45)
        _duration = State(initialValue: task.duration)
        _priority = State(initialValue: task.priority)
        _urgency = State(initialValue: task.urgency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Task title", text: $title)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                    TextField("Task details", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
                Text(task.eisenhowerQuadrant.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(quadrantColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Urgency", selection: $urgency) {
                    ForEach(TaskUrgency.allCases, id: \.self) { value in
                        Text(valueLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Duration", selection: $duration) {
                    ForEach(TaskDuration.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.menu)

                if duration == .timed {
                    Stepper(value: $minutes, in: 10...240, step: 5) {
                        Text("\(minutes)m")
                    }
                    .frame(maxWidth: 120)
                } else {
                    Text(duration.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Focus next") {
                    viewModel.selectedTask = task
                }
                .disabled(!task.requiresFocus)
                Button("Complete") {
                    viewModel.markTaskComplete(task)
                }
                .disabled(task.isCompleted)

                Spacer()

                Button(role: .destructive) {
                    viewModel.deleteTask(task)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onChange(of: title) { _ in
            persistChanges()
        }
        .onChange(of: details) { _ in
            persistChanges()
        }
        .onChange(of: priority) { _ in
            persistChanges()
        }
        .onChange(of: urgency) { _ in
            persistChanges()
        }
        .onChange(of: minutes) { _ in
            persistChanges()
        }
        .onChange(of: duration) { _ in
            persistChanges()
        }
        .onChange(of: task.id) { _ in
            title = task.title
            details = task.details
            minutes = task.estimatedMinutes ?? 45
            duration = task.duration
            priority = task.priority
            urgency = task.urgency
        }
    }

    private func persistChanges() {
        viewModel.update(
            task: task,
            title: title,
            details: details,
            estimatedMinutes: duration == .timed ? minutes : nil,
            duration: duration,
            priority: priority,
            urgency: urgency
        )
    }

    private var quadrantColor: Color {
        switch task.eisenhowerQuadrant {
        case .doNow: return .red
        case .schedule: return .orange
        case .delegate: return .blue
        case .eliminate: return .gray
        }
    }

    private func valueLabel(_ urgency: TaskUrgency) -> String {
        switch urgency {
        case .urgent: return "Urgent"
        case .upcoming: return "Upcoming"
        case .flexible: return "Flexible"
        }
    }
}
