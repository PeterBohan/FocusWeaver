# FocusWeaver

A native macOS productivity app that brings task management, adaptive Pomodoro sessions, and camera-based attention estimates into one workspace. Built with SwiftUI, FocusWeaver helps you plan work, stay on task, and review your focus habits.

## Features

- **Task inbox:** Create, edit, complete, and delete tasks. Set priority, urgency, and a specific duration, or keep tasks untimed or all-day.
- **Task suggestions:** Find potential follow-up tasks from Apple Mail and preparation tasks from upcoming Apple Calendar events. Suggestions use keyword-based filters for work and school activities.
- **Priority planning:** Organize tasks into Eisenhower quadrants and view recommended focus blocks in a list or timeline.
- **Adaptive Pomodoro sessions:** Adjust focus blocks and breaks using attention estimates and past session results.
- **Camera-based focus tracking:** Use Apple's Vision framework to estimate attention from face landmarks, head pose, and eye signals. Sessions enter a hold when you leave the camera frame.
- **Analytics and daily reports:** Review attention trends, interruptions, task completion, and recent focus sessions.
- **Local persistence:** Keep tasks, focus metrics, session state, and dismissed suggestions between launches.

## Requirements

- macOS 13 or later.
- Swift 6.2 or later, with the macOS SDK and command-line build tools configured. The package declares Swift tools version 6.2.
- A built-in or external camera for camera-based focus sessions.
- Apple Mail configured with an account and/or events in Apple Calendar to use the respective task suggestions.

## Get started

Clone the repository and run the app from the folder containing `Package.swift`:

```bash
git clone https://github.com/PeterBohan/FocusWeaver.git
cd FocusWeaver
swift build
swift run FocusWeaverMac
```

If you downloaded a ZIP instead, extract it and open a terminal in the extracted project folder before running the Swift commands.

### Install as a macOS app

The included script builds a release executable, generates the app icon, and assembles the app at `/Applications/FocusWeaver.app`:

```bash
./Scripts/install-focusweaver-app.sh
open /Applications/FocusWeaver.app
```

Your user account must have permission to write to `/Applications`. Running the script again updates the app at the same location.

## Using FocusWeaver

1. Open **Inbox** and add a task. Choose **Specific duration** if you want to use it in a camera focus session.
2. Click **Refresh** to request suggestions from Apple Mail and Calendar. Grant the relevant macOS permissions when prompted.
3. Review task priorities and the suggested schedule in the planner.
4. Select a timed task and start a focus session. Allow camera access when prompted. You can also toggle a session with **Command + Shift + Space**.
5. Review your attention trends, session history, and daily report as you work.

Untimed and all-day tasks remain in your task list without camera focus blocks.

## Permissions and data

FocusWeaver uses camera access for focus tracking, Automation access to read Apple Mail messages, and Calendar access to suggest preparation tasks. You can manage these permissions in **System Settings → Privacy & Security**.

Camera frames are analyzed locally with Apple's Vision framework. The current focus detection code does not record video or upload camera frames. Attention and blink values are heuristic estimates and can vary with lighting, camera position, and face visibility.

App data is stored as JSON in:

```text
~/Library/Application Support/FocusWeaver/
```

| File | Contents |
| --- | --- |
| `tasks.json` | Saved tasks |
| `focus_metrics.json` | Recorded focus metrics |
| `session_state.json` | Session state and history |
| `dismissed_task_keys.json` | Dismissed imported tasks, to prevent repeated suggestions |

Imported task details may contain text from messages or calendar events. These local data files are outside the repository.

## Project structure

```text
.
├── Package.swift
├── README.md
├── README-macOS.md
├── Scripts/
│   ├── generate-app-icon.sh
│   └── install-focusweaver-app.sh
└── Sources/FocusWeaverMac/
    ├── App/          # App entry point and commands
    ├── Models/       # Tasks, scheduling, and focus metrics
    ├── Services/     # Detection, task extraction, planning, and storage
    ├── Utilities/    # Shared statistics helpers
    ├── ViewModels/   # App state and workflow coordination
    ├── Views/        # SwiftUI screens
    └── Resources/    # Info.plist and app icon assets
```

## App icon

The icon source is `Sources/FocusWeaverMac/Resources/AppIconSource.png`. To regenerate `AppIcon.icns` without installing the app:

```bash
./Scripts/generate-app-icon.sh
```
