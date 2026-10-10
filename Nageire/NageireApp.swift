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
    static func makeModel() -> AppModel {
        #if DEBUG
        // Started for the tests or for a preview, the app would otherwise be the app of whoever
        // works on it: it would read their tokens from the Keychain and send and fetch their notes.
        // Xcode sets a variable for each of the two.
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .sample(.signedOut)
        }
        // Launched with `-sampleData stream`, the app shows the sample of the design in that scene.
        if let scene = UserDefaults.standard.string(forKey: "sampleData").flatMap(SampleScene.init) {
            return .sample(scene)
        }
        #endif
        return .live()
    }
}

extension FocusedValues {
    /// Asks the window that has focus for a new note. Nil while that window cannot write one, as on the sign-in screen.
    @Entry var newNoteRequests: NewNoteRequests?
}

struct NoteCommands: Commands {
    @FocusedValue(\.newNoteRequests) private var newNoteRequests
    @FocusedValue(\.editorRequests) private var editorRequests

    var body: some Commands {
        // Command-N is the key for a new note, not for a new window.
        CommandGroup(replacing: .newItem) {
            Button("New Note") { newNoteRequests?.request() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newNoteRequests == nil)
        }
        CommandMenu("Format") {
            Button("Add Photos…") { editorRequests?.addPhotos?() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editorRequests?.addPhotos == nil)
            Divider()
            Group {
                Button("Bold") { editorRequests?.request(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { editorRequests?.request(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Add Link") { editorRequests?.request(.link) }
                    .keyboardShortcut("k", modifiers: .command)
            }
            .disabled(editorRequests == nil)
        }
    }
}
