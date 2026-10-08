# Work plan for the redesign

This is how the redesign is built, in whatever environment picks it up. The decisions are made and recorded; what is left is the building, in the order below, with each step verified against the design before it is merged.

## Where the decisions are

- [concept.md](concept.md) holds the app's principles and the decisions already settled. It is the document a decision moves into once it is made.
- [ux-redesign.md](ux-redesign.md) holds the decisions of the redesign: titles, the editor, saving, attachments, the look, navigation, capture from outside, sign-in, sync and deletion, the words.
- [on-device-model.md](on-device-model.md) holds the three things the on-device model does and the rules it obeys.
- [design-reference.md](design-reference.md) holds the design to match, with the tokens and the renders in its folder.
- [ui-guide.md](ui-guide.md) says how the UI is built in SwiftUI: where views and state live, how each component is made, the sample data for previews, and the editor.
- [design-brief.md](design-brief.md) is the brief the prototype was made from. It is kept for the next run of Claude Design, if there is one, and is not a source for building.

Read the first five before starting a phase, and load the `writing-conventions` skill before writing anything into the repository.

## Where to work

The app needs Xcode 27 on macOS to build and test, which in turn needs macOS 26.6 or later on Apple silicon, and every phase changes what is on screen, so a phase is done in an environment with Xcode and a simulator. A cloud session on Linux can read, write, and commit but cannot build or see the app; it is fine for the documents, not for a phase.

## How a phase is done

A phase is built as several pull requests, each one item of its checklist or a few items that touch the same screen. A small pull request is read in one sitting, and a failure in CI is found before anything is built on top of it. The heading of a phase names the branch of its last pull request, and the phase lists the others once they are planned.

1. Branch from `main` as `feature/<name>`, one branch per pull request, after the pull request before it is merged.
2. Keep structural changes (renames, moves, extractions) in their own commits, before the behavioral ones. A commit subject is around fifty characters in the imperative, the body holds the why, and nothing in the message says a model took part.
3. Build the phase in the order its checklist gives, and run the tests on macOS and on the iOS simulator before every push: `xcodebuild test -scheme Nageire -destination 'platform=macOS'` and the same with `'platform=iOS Simulator,name=iPhone 17'`. CI runs both on every pull request.
4. Review the branch before anyone else does, with the `simplify` and `review-pr` skills, and fix what they find.
5. Verify the screens the pull request touches against the design (below).
6. Open the pull request. Its body has three sections, as the earlier ones do: Background, Not done, and Where to look. The `create-pr` skill produces it, and the review that skill would run is the one of step 4, not a second one.
7. The last pull request of a phase updates the Status paragraph of the README and moves the decisions the phase settled from ux-redesign.md into concept.md. It strikes nothing from ux-redesign.md: it stays the record of why.

## Verifying against the design

- Run the app on an iPhone 17 simulator and on macOS, in light and in dark, and take screenshots with `xcrun simctl io booted screenshot` and the system's screenshot on macOS. Launched with `-sampleData stream`, a debug build shows the sample of the prototype without an account, as ui-guide.md describes: `xcrun simctl launch booted com.yamat47.Nageire -sampleData stream -AppleLanguages "(ja)" -AppleLocale ja_JP`, and the same arguments after `open -n Nageire.app --args` on macOS.
- Put each screenshot beside its screen in `docs/design/iphone-light.png`, `iphone-dark.png`, `mac-light.png`, and `mac-dark.png`. The two should differ only where the platform draws its own control differently from the web prototype: the keyboard, the glass, the fonts on a device that has Hiragino.
- Check the measurements against design-reference.md where the eye cannot tell: the gutter, the row padding, the control heights, the radii.
- Set Dynamic Type to the largest accessibility size once and confirm nothing is clipped and the bottom bar still holds the search field and the button.
- Turn VoiceOver on once and confirm every icon-only button reads its label.
- Confirm the color sets are the exact values in `docs/design/tokens.css`; the contrast of the pairs was checked there and holds only for those values.

## Before phase 1: move the project to Xcode 27 (`feature/xcode-27`)

The project was last built with Xcode 26. Xcode 27 shipped on September 14, 2026 with the iOS 27 and macOS 27 SDKs and needs macOS 26.6 on Apple silicon (Apple's [Xcode release notes](https://developer.apple.com/documentation/xcode-release-notes)), and GitHub's hosted runners now carry one image per Xcode version instead of per macOS version. This step is two pull requests, the tools and then the language mode, before any screen changes, so that a build failure from the tools is never mixed with one from the redesign.

1. Open the project in Xcode 27, accept the project changes it proposes, and run the tests on macOS and on an iPhone simulator. Fix what the new SDKs flag before anything else. One warning waits: the closure in the focused value that carries the command for a new note. Replacing it changes how Command-N reaches the list, which no test covers, and that command is rebuilt with the toss sheet in phase 1.
2. The rule in concept.md is that the minimum OS is the current release, which is now iOS 27 and macOS 27. Raise both deployment targets to 27 and change the numbers in concept.md and the README's Building paragraph, or, if 26 is kept so that devices left on it are not excluded, record that decision in concept.md in place of the rule. Either way the document and the project must agree.
3. In `.github/workflows/test.yml`, change `runs-on: macos-26` to the `xcode-27` label, which runs on macOS 27 on arm64 runners and was in public preview as of September 2026 (GitHub's changelog of [July 16](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview) and [September 10, 2026](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27)). Keep the `iPhone 17` destination if that image has the simulator, otherwise use the current iPhone it has, and change the same name in CLAUDE.md and in this document.
4. Every configuration in `Nageire.xcodeproj` sets `SWIFT_VERSION = 5.0`, and the Swift skills under `.claude/skills`, which came in with pull request #13, were checked against Swift 6.4 and prefer language mode 6. Move to mode 6 in a second pull request right after this one (`feature/swift-6`), before phase 1 writes new Swift: turn the mode on, fix what the compiler flags, and record the mode in CLAUDE.md. If mode 5 is kept for now, record that instead, so that the skills' mode-6 rules are read as later rather than as broken.
5. Note in the pull request which Xcode build and which runner image version ran the tests.

## Phase 1: the look (`feature/redesign-look`)

The phase changes no file format and no API call. It ships on its own.

Its pull requests, in order, with the items each carries:

- `feature/redesign-tokens`: 1 and 2, with the button styles and the sample data of ui-guide.md.
- `feature/redesign-stream`: 3 and 5.
- `feature/redesign-toss`: 4 and 6, with the vase symbol. The command for a new note stops passing a closure through a focused value here; the Xcode 27 SDK warns that a closure there invalidates what depends on the value on every update.
- `feature/redesign-note`: 7.
- `feature/redesign-settings`: 8.
- `feature/redesign-undo`: 9.
- `feature/redesign-sign-in`: 10.
- `feature/redesign-look`: 12 over the whole phase.

The words of item 11 go in with the screen that shows them.

1. Add the color sets to `Assets.xcassets` with both appearances, set `AccentColor` to the accent, and add the `ShapeStyle` extension with the token and alias names.
2. Add the type helpers: the note body style with its leading, the scaled heading sizes, the derived style.
3. Rebuild the stream: a plain list with a section per day (今日, 昨日, then the date with its weekday), the new row with the display title, two lines of excerpt, and the meta line; the display title rule from ux-redesign.md (an `# ` first line, else the first line cut at its first sentence or forty characters).
4. Put the search field and the primary button into the bottom bar on iPhone. Keep search in the sidebar on macOS.
5. Replace the list's footer with the unsent mark on each row and the banner above the list for a refused write only.
6. Rebuild the toss sheet with its header (close, timestamp, the save button), keeping the existing draft behavior and the plain text view. It has no accessory bar in this phase, so the comparison against the toss-sheet render stops at the editor.
7. Rebuild the note screen as one surface with the header line, the share and menu buttons, and the menu holding GitHub で開く and 削除. Editing stays as it is in this phase, with the plain text view, so that the phase does not wait for the editor.
8. Restructure Settings into the groups of the design, including the sync group with 今すぐ送信, the 書く group with the serif choice, and the on-device group in its unavailable state, the sentence alone with no switch, since the model is not wired until phase 5. Leave 振り返る as 準備中.
9. Replace the deletion confirmation with the undo bar: the row leaves at once, the bar stays ten seconds and waits while the app is not in front, the deletion is queued when it goes, and `UndoManager` handles Command-Z and the shake.
10. Rebuild sign-in and the device-code screen with the step list, the code card, the two footnotes, and the primary and secondary buttons in the design's order. Replace the logo image with the mark.
11. Put in the words: 完了 for the sheet's action, 書きかけ for the draft's row, 新しいメモ, 未送信, 送信済み. Both languages in `Localizable.xcstrings`.
12. Verify every screen as above, then the pull request.

## Phase 2: the editor (`feature/redesign-editor`)

Its pull requests, in order, with the items each carries:

- `feature/redesign-editor-view`: 1 up to the faint marks, in the toss sheet and in the note screen's edit mode, with the thumbnails under their lines. The raw line of an image and the address of a link stay visible here.
- `feature/redesign-editor-hiding`: the rest of 1, the raw image line and the link's brackets and address shown only on the line that holds the caret. ui-guide.md names this the hardest piece and has it come last.
- `feature/redesign-editor-lists`: 2 and 3, since the accessory bar and the Format menu insert the marks that Return continues.
- `feature/redesign-editor-surface`: 4, 5, and 6. A tapped checkbox is an edit, and an edit is saved as typed, so the three arrive together.
- `feature/redesign-editor`: 7 over the whole phase.

1. The TextKit 2 text view in a representable for iOS and macOS, with the Markdown it holds styled in place: headings, emphasis, code, list markers, task checkboxes, links with faint marks, and the raw line of an image or the address of a link shown only while the caret is on that line.
2. List continuation on Return, and an empty item ending the list.
3. The accessory bar on iOS and the Format menu with Command-B, Command-I, and Command-K on macOS.
4. Reading and editing as one surface: opening a note does not raise the keyboard; tapping into the text does.
5. Saving as typed to the device and one commit when the note is closed, when another is selected, when the app goes to the background, or after thirty seconds without typing. Remove Edit, Save, and Cancel from the note screen.
6. A tapped checkbox is an edit like any other.
7. Verify on both platforms with long notes, nested lists, and a note that holds only an image line.

## Phase 3: attachments (`feature/redesign-attachments`)

1. The folder beside the note, the file naming, and the relative link, as ux-redesign.md gives them.
2. Photos from the library and the camera, files from the file picker, paste, and drag and drop on iPad and macOS.
3. Resizing to 2048 on the long side with the setting for 4096 and the original, HEIC to JPEG.
4. The outbox sends a note's files before the note; a waiting file counts among the unsent; the Wi-Fi switch, off by default.
5. Thumbnails in the editor, full screen on tap, and removal of a file no line names any more at the next send.
6. Lazy fetching of other devices' attachments when a note is opened.
7. Verify with a note of five photos sent and received across two simulators signed into the same repository.

## Phase 4: capture from outside (`feature/redesign-capture`)

1. An app group so that the share extension and the app share the store and the outbox.
2. The share extension for text, a link, and images.
3. The Control Center control and the Lock Screen widget that open the sheet.
4. The App Shortcut Nageire に投げ入れる.
5. On macOS the menu bar item with Command-Shift-N, Command-Return to send, and Escape to keep the draft.

## Phase 5: looking back (`feature/redesign-lookback`)

1. The month picker from a day header.
2. The on-device model in the order on-device-model.md gives: topics and search by topic, related notes, and then tentative titles only if the review over thirty real notes passes. Wire the Settings switch and the availability sentence.
3. The year view, then reflection, each as its own decision when reached.

## Decisions not to reopen

These were weighed and settled; a phase builds them rather than revisits them.

- No title field. A heading in the text or a derived display title.
- Markdown styled in place, not WYSIWYG, and no separate preview.
- A button for a new note, saving as typed for an existing one.
- Attachments in the folder beside the note, linked relatively, photos reduced to 2048 by default.
- Paper, ink, and vermilion, with the token values in `docs/design/tokens.css`. Vermilion fills one control per screen.
- The undo bar for deletion, ten seconds, in place of the confirmation.
- The unsent mark in ink-2, not in the accent.
- The on-device model does three things, has no name, and is explained in one sentence in Settings.
- Nothing the model produces is written into a file unless the person tapped.

## Open when reached

- Whether the Markdown marks are hidden off the current line in a later version.
- Whether a short video gets a thumbnail.
- Whether the quick-entry panel on macOS is a separate process.
- What the year view shows beyond a mark per day.
- Whether tentative titles ship at all; the review decides.
