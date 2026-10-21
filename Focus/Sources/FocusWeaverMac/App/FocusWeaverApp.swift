import SwiftUI
import AppKit

@main
struct FocusWeaverApp: App {
    @StateObject private var viewModel = FocusWeaverViewModel()
    @State private var didActivateApp = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    guard !didActivateApp else { return }
                    didActivateApp = true
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            CommandMenu("Focus Session") {
                Button(action: viewModel.toggleFocusSession) {
                    Text(viewModel.isFocusSessionActive ? "End Session" : "Start Session")
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }

        Settings {
            AnalyticsView()
                .environmentObject(viewModel)
                .frame(minWidth: 420, minHeight: 480)
        }
    }
}
