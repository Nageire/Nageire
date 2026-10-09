# Nageire

Toss in your thoughts, arrange them later.

Nageire is a notes app for iOS and macOS. You write a note, and it is saved as a Markdown file in your own GitHub repository. There are no folders or tags to choose while you write. Later, a language model reads the notes you have piled up and helps you look back across them: a career retrospective, a history of doctor visits, a year of a diary.

The name comes from nageire (投入), a style of ikebana in which flowers are placed in a tall vase as if tossed in, without a fixed form.

## How it works

- Each note is one Markdown file named by its timestamp, stored by month in a GitHub repository you choose.
- Notes are saved on the device first and sent to GitHub in the background.
- There is no server run by the developer. Your data lives on your device and in your GitHub repository, and nothing is collected.
- Reflection runs on a language model with your own API key. Before any note content is sent to it, the app asks for your consent.

Since the files are plain Markdown in your repository, they stay readable with any other tool if you stop using Nageire.

## Status

Nageire is at the sixth step of its roadmap. You can sign in with GitHub, choose the repository for your notes, write notes that are saved on the device and sent to that repository, read and search every note the repository holds, and edit and delete them. Reflection with a language model is not built yet and is set aside for now. The design and the reasons behind it are in [docs/concept.md](docs/concept.md). The redesign of the whole app is settled, and its first two phases are built: the look, with paper, ink, and vermilion, the stream grouped by day, the bar at the bottom with search and the button for a new note, the undo for deletion, and the restructured Settings and sign-in; and the editor, with Markdown styled in place, lists that continue on Return, a bar of marks above the keyboard, and notes saved as they are typed, with a commit when the writing pauses. Attachments, capture from outside the app, and looking back follow in that order; the decisions are in [docs/ux-redesign.md](docs/ux-redesign.md) and the order of work in [docs/workplan.md](docs/workplan.md).

## Building

Open `Nageire.xcodeproj` in Xcode 27 and run the `Nageire` scheme on an iPhone simulator or on the Mac. The app needs iOS 27 or macOS 27. The tests run from the same scheme.
