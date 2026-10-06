import SwiftUI

@main
struct NageireApp: App {
    @State private var model = NageireApp.makeModel()

    var body: some Scene {
        #if os(macOS)
        // One window, not a group: every window would show the same list. Closing it quits
        // the app, as the system does for an app whose only scene is a single window.
        Window(Text(verbatim: "Nageire"), id: "main") {
            RootView()
                .environment(model)
                .defaultAppStorage(model.defaults)
        }
        .defaultSize(width: 900, height: 600)
        .commands { NoteCommands() }

        Settings {
            SettingsView()
                .environment(model)
                .defaultAppStorage(model.defaults)
        }
        #else
        WindowGroup {
            RootView()
                .environment(model)
                .defaultAppStorage(model.defaults)
        }
        .commands { NoteCommands() }
        #endif
    }
}

extension NageireApp {
    private static func makeModel() -> AppModel {
        #if DEBUG
        // Launched with `-sampleData YES`, the app shows the sample of the design.
        if UserDefaults.standard.bool(forKey: "sampleData") {
            return .sample()
        }
        #endif
        return .live()
    }
}

extension FocusedValues {
    /// Starts a new note in the window that has focus. Nil while that window cannot write one, as on the sign-in screen.
    @Entry var startNewNote: (() -> Void)?
}

struct NoteCommands: Commands {
    @FocusedValue(\.startNewNote) private var startNewNote

    var body: some Commands {
        // Command-N is the key for a new note, not for a new window.
        CommandGroup(replacing: .newItem) {
            Button("New Note") { startNewNote?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(startNewNote == nil)
        }
    }
}
