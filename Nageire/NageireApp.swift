import SwiftUI

@main
struct NageireApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        #if os(macOS)
        // One window, not a group: every window would show the same list, and a single
        // window stays in the Window menu, which is how it comes back after being closed.
        Window(Text(verbatim: "Nageire"), id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 900, height: 600)
        .commands { NoteCommands() }

        Settings {
            SettingsView()
                .environment(model)
        }
        #else
        WindowGroup {
            RootView()
                .environment(model)
        }
        .commands { NoteCommands() }
        #endif
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
