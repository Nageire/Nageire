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

Nageire is at the second step of its roadmap. You can sign in with GitHub, choose the repository for your notes, and write notes that are saved on the device and sent to that repository. The list of notes and search are not built yet. The design and the reasons behind it are in [docs/concept.md](docs/concept.md).

## Building

Open `Nageire.xcodeproj` in Xcode 26 and run the `Nageire` scheme on an iOS 26 simulator or on macOS 26. The tests run from the same scheme.
