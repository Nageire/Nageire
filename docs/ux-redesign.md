# Nageire UX redesign

This document proposes how Nageire looks and behaves from the seventh step of the roadmap on. It starts from what is built through step 6 (pull request #12: the sign-in path laid out up front, the icon drawn from layers) and from [concept.md](concept.md), whose principles it keeps. Where it changes a decision recorded there, it says so. A decision here moves into concept.md once it is made, and the design that goes with this document is in [design-reference.md](design-reference.md).

## Two moments

The app serves two moments that want different things. Tossing in wants the fewest decisions and the shortest path to a text field. Looking back wants what was tossed in to be found, read, and recognized. Every choice below is checked against both: nothing is asked at the moment of writing, and nothing is lost for the moment of reading.

## Titles

A note has no title field. The list and the note's header show a display title derived from the text, and a person who wants a real title writes one as a Markdown heading.

- When the first non-blank line starts with `# `, that line without the marker is the title, and the excerpt in the list starts at the next line.
- Otherwise the first non-blank line is the title, cut at the end of its first sentence or at 40 characters, whichever comes first, and the excerpt is what follows. The Markdown marks are taken out of it as out of the excerpt, so that a note that begins with a task or in bold reads as its words. A sentence ends at 。, ！, or ？, and at a period followed by a space or the end of the line, so that a decimal or an address does not end one. A note whose only line is an image is called by the file's name.
- The heading button in the editor's accessory bar inserts `# ` at the start of the first line. That is the whole of "adding a title".
- The file name stays the timestamp. A name derived from the title would change with every edit of the first line, and a rename on GitHub is a delete and an add, which breaks the one-request-per-file rule and the file's history.
- Nothing goes into the front matter for it. A title in the body is shown by every Markdown renderer, GitHub's file view included.

A title field is a decision before writing, which principle 2 rules out. Apple Notes shows that the first line serves as the title for anything short, and the `# ` convention gives a long entry a real heading without a second field.

## The editor

Markdown stays the text in the editor. The editor styles it in place: headings larger, emphasis bold or italic, list markers aligned, task items drawn as checkboxes, links colored, images shown as thumbnails under their line. The syntax characters stay visible in a faint color. Reading and editing are one surface; there is no Edit button, no preview, and no WYSIWYG.

WYSIWYG was considered and turned down. A rich-text model has to be converted to Markdown on every save, and nested lists, tables, and raw HTML lose something in the round trip, so what is written would not be what is stored, against principle 1. A format that is hidden cannot be checked by eye. The plain text view the app has today was turned down as well: a heading, a list, and a link all look the same, and a photo is a line of brackets, which is unreadable on a phone for anything longer than a few lines.

- The marks are faint, not hidden, with two exceptions. An image line shows only its thumbnail and a link only its text while the caret is elsewhere; the raw `![name](path)` and the brackets and address of a link appear, faint, only on the line that holds the caret. Every other mark, the `#`, the `*`, the backtick, and the `-`, stays faint on every line. Hiding those too except on the current line (Obsidian's live preview, Bear) reads better but moves the text as marks appear and disappear, and is a larger build; it can follow without any change to the files. A setting shows the marks in full ink, which is also what a reader who needs contrast wants.
- `- [ ]` is a checkbox that toggles with a tap. A toggle is an edit of the file like any other.
- `![alt](path)` shows the image in place of the line, with the file name and size as a caption. Tapping it opens it full screen. When no line in the note names a file any more, the file is removed at the next send.
- Return inside a list continues the list, and Return on an empty item ends it. On iOS the accessory bar above the keyboard holds photo, camera, file, heading, list, checklist, bold, link, and a key that lowers the keyboard. On macOS, Command-B, Command-I, and Command-K insert the marks, and the Format menu lists them.
- Opening a note does not raise the keyboard. Tapping into the text does.
- SwiftUI's `TextEditor` with `AttributedString` on iOS 26 styles text but has no inline attachments. Thumbnails under a line need TextKit 2 through a `UIViewRepresentable` and an `NSViewRepresentable`, which is the one custom view in the app.

## Saving and commits

A new note keeps its button. The draft is saved on the device on every change and survives closing the sheet and relaunching the app; "完了" sends it as one commit, as today. The toss is a gesture with an end, and a gesture with an end deserves a button.

An existing note has no Edit, Save, or Cancel. Changes are saved on the device as they are typed, and one commit is sent when the note is closed, when another note is selected, when the app goes to the background, or after thirty seconds without typing, whichever comes first. A note held open for an hour of writing gets a handful of commits, not hundreds. The Edit mode exists today to protect an edit from being discarded by navigating away; saving as typed removes the thing it protects against. The conflict rule from concept.md stays: the change that arrives last wins.

## Attachments

A note's files live in a folder beside it, `notes/YYYY/MM/<timestamp>-<suffix>/`, named like the note without `.md`. A file keeps its own name with characters GitHub cannot take replaced, and a second file with the same name gets a counter. The note links to it relatively, `![](<timestamp>-<suffix>/IMG_0421.jpeg)`, so GitHub's file view shows the image.

The folder sits beside the note rather than under a top-level `attachments/` because the links stay short, the note and its files are one unit to delete or to move, and nothing about the layout has to be known to find a note's files. Principle 3 widens from "one note, one file" to "one note, one file and its folder"; every file is still one request.

- A photo is sent as JPEG with its long side reduced to 2048 pixels, which turns the 3 to 5 MB a camera produces into a few hundred kilobytes. A setting offers 4096 pixels and the original. A diary with a photo a day stays under the 1 GB GitHub recommends for years at 2048 pixels and does not at the original size.
- A PDF or any other file is sent as it is. Above 25 MB the app warns; above 100 MB the API refuses, and the app says so before trying.
- The outbox sends a note's files before the note, so the note on GitHub never names a file that is not there yet. A file still waiting is counted among the unsent.
- A refresh lists the files of other devices but fetches one only when its note is opened, and keeps it afterwards. Thumbnails are made on the device.
- A file comes in from the accessory bar (library, camera, files), from paste, from drag and drop on iPad and macOS, and from the share extension.
- A switch in Settings sends photos only on Wi-Fi. It is off by default.
- Git LFS is not reachable through the Contents API and is not used. Video is a file like any other, with no preview beyond the system's.

## Look and tone

The icon already has the palette: paper, ink, and vermilion. The app adopts it. The accent color becomes vermilion, the canvas is paper rather than the system's white or grouped gray, text is ink, and vermilion appears on the one primary action and on marks that ask for attention, nowhere else.

| Token | Light | Dark | Where |
| --- | --- | --- | --- |
| paper | `#F2EDE3` | `#1F1D1B` | The canvas. The dark value is the icon's dark background. |
| paper-raised | `#FAF7F1` | `#2A2724` | Sheets, cards, the floating bar. |
| paper-sunken | `#E8E1D4` | `#161412` | Inputs, code, image placeholders. |
| hairline | `#DAD2C3` | `#3A3631` | Every rule. |
| ink | `#2A2825` | `#EDE7DB` | Text. |
| ink-2 | `#655F56` | `#A9A194` | Excerpts, dates, captions. 4.9:1 on paper-sunken as well; `#6B655C` was 4.4:1 there. |
| ink-faint | `#B9B1A3` | `#5E5850` | Markdown marks and placeholders only. Not for anything that must be read. |
| accent | `#B8503A` | `#D86A52` | Fills: the toss button, the checked box, the switch. |
| accent-text | `#9E3F2B` | `#E07A61` | Links and vermilion text on paper. 5.6:1. |
| accent-wash | `#F1D9D1` | `#3B2620` | The selected row on macOS, the warning banner. |
| on-accent | `#FAF7F1` | `#1F1D1B` | The label on an accent fill. 4.6:1 in light, 4.9:1 in dark. |

The reference design is the interactive prototype made with Claude Design from [design-brief.md](design-brief.md), at https://claude.ai/artifact/Kjk517nBqpUeXyyhJ3UsVY. It holds the nine iPhone screens, the macOS window with the quick-entry panel, and both appearances. Its stylesheet carries these tokens, the type scale, the spacing, and the motion as CSS custom properties, and its component library is the list of views to build. [design-reference.md](design-reference.md) carries both, with the renders, so that no environment needs the artifact. The static canvas "Nageire UX Redesign" came before it and is kept only as the record of the exploration.

The brand vermilion `#C1563F` stays in the icon and the logo. On a button with light text it reaches 4.5:1 only just, so fills use the slightly deeper `#B8503A`, and in dark mode the button carries ink text, because light text on `#D86A52` fails.

The type is the system's: SF Pro and Hiragino Sans, following Dynamic Type. The body of a note is 17 points with a leading of 1.65 for Japanese. A setting puts the body in a serif (Hiragino Mincho ProN, New York) and leaves the rest of the app in sans. Headings inside a note are 24, 20, and 17 points, semibold. Code and file names are SF Mono.

Surfaces are separated by hairlines. A shadow belongs only to what floats: the bottom bar, the toss button, a sheet. On iOS 26 the system's glass toolbars sit over paper and take their tint from the accent; the app draws no toolbar of its own. Icons are SF Symbols, with one custom symbol, the vase from the logo, for the toss.

Motion is one gesture. When a note is tossed, the sheet goes down and the new row settles in at the top of the list. Nothing else animates beyond what the system does.

## Navigation

On iPhone the app opens on the stream: every note, newest first, grouped by day under "今日", "昨日", and then the date with its weekday. A row shows the display title, up to two lines of excerpt, the time, the number of attachments, and whether the note is still unsent.

- A bar at the bottom holds the search field and the button for a new note, which is the vase alone, as the compose button of Apple's Notes is an icon alone in the same bar. iOS 26 puts search at the bottom, and the thumb reaches both.
- The button opens a sheet. Closing the sheet keeps the draft, and while a draft is waiting the stream shows it as a quiet row at its top, "書きかけ" with the first line of the text, which opens the sheet too. The button itself says nothing of it.
- A row opens the note full screen, where reading and editing are the same surface. Back returns to the stream. On the right are Share and a menu with "GitHub で開く" and "削除".
- Settings sit behind the account button at the top right.
- Search filters the stream as the query is typed, and a day header stays above its matches.
- Time is the only axis. There are no folders and no tags. Tapping a day header opens a month picker. A year view, a grid of days with a mark on each day that has notes, is the place to look back from and comes with reflection, which gets its button in the header of the stream. The bottom bar keeps its two items.

In a wide window, on iPad and macOS, the list stays beside the note as today. Command-N writes in the detail column, search is in the sidebar, and the sync line sits at the bottom of the sidebar. The selected row is tinted with accent-wash.

## Capture from outside the app

"Writing is one tap away" has been measured from inside the app. Most tosses begin somewhere else.

- A share extension takes text, a link, or images from any app and makes a note of them. An image alone is a note of one image.
- A Control Center control and a Lock Screen widget open the app straight into the sheet.
- An App Shortcut, "Nageire に投げ入れる", takes text from Siri, Spotlight, and the Action button.
- On macOS, a menu bar item with a global shortcut (Command-Shift-N) opens a small panel from any app. Command-Return sends and closes it; Escape closes it and keeps the draft.

The share extension and the main app write to the same outbox, so an app group holds the store.

## Sign-in and the first run

The path from pull request #12 stays: the three steps shown before the first one starts, GitHub opened in the browser, and the repository list read again when the app comes back to the front.

- "GitHub を開く" also puts the code on the clipboard. "コードをコピー" stays for a person who opens GitHub on another device.
- The code screen shows which of the three steps it is.
- After the repository is chosen, the empty stream says what to do and mentions the share sheet.
- The empty repository list keeps its explanation of installing, and a footnote links to GitHub's new-repository page with private visibility selected, for a person who has no repository yet. The app still creates none.

## Sync visibility and deletion

Each row carries its own state: nothing when the note is sent, a hollow circle with "未送信" when it is not. The footer the list has today goes away. A banner appears above the stream only when GitHub refused and the app cannot write, with a link to Settings. A transient failure shows nothing; the hollow circles already say it. Settings gains a section with the count of unsent items, the time of the last send, "今すぐ送信", and the Wi-Fi switch.

Deleting a note, by swipe or from the menu, removes the row at once and shows "削除しました" with "取り消す" in a bar at the bottom for ten seconds. The deletion is queued when the bar goes away, and the bar waits while the app is not in front. Within that window Command-Z on macOS and the shake and three-finger gestures on iOS undo it as well, through the system's undo manager. Ten seconds is the default Mail gives "Undo Send". This changes the decision in concept.md that deleting asks for confirmation every time: a confirmation is answered without being read from the third time on, while an undo asks nothing and still protects. Apple's other pattern for deletion, a "Recently Deleted" list, would need the app to read the Git history, which the one-file-at-a-time API does not give it, so the history stays the only trash.

## Words

| English | Japanese | Where |
| --- | --- | --- |
| New note | 新しいメモ | What VoiceOver and the tooltip call the vase button, and the menu command. |
| Done | 完了 | The sheet's action: the note is kept and sent, as Apple's Journal ends an entry. The close button keeps the draft instead. |
| Draft | 書きかけ | The row at the top of the stream while a draft waits. |
| New note | 新しいメモ | The sheet's label. |
| Unsent, Sent | 未送信, 送信済み | The row and the note header. |
| Deleted, Undo | 削除しました, 取り消す | The undo bar. 取り消す is the system's word for Undo, in the Edit menu, in Mail's 送信を取り消す, and in Photos; the bar read 元に戻す in the design, which is the word of Gmail and Slack, and would have differed from the Edit menu beside it. |
| Look back | 振り返る | The reflection entry, when it ships. |
| Note | メモ | Everywhere. Not ノート. |

The voice is plain and short. The app does not congratulate and uses no exclamation marks. The buttons borrow the system's words and shapes. "投げ入れる" was the primary action at first, on the button that opens the sheet and on the one that sends the note, and was turned down: the same word in both places left it unclear which of the two makes a note, and a word of the app's own on a button reads as the app admiring itself. The name and the tagline keep the image.

## What changes in the files

The format stays readable by any tool. A title is a Markdown heading, not a front matter field. A note's attachments are in the folder beside it and are linked relatively. The `created` and `updated` fields stay as they are. A folder the app did not write is left alone, as a file without front matter is today.

## Order of work

1. The look: accent and palette, type, the stream with day groups and display titles, the bottom bar, the restructured Settings, the sync marks and the banner, the undo for deletion, and the new words. This step ships on its own and changes no file.
2. The editor: Markdown styled in place, one surface for reading and editing, saving as typed with coalesced commits, the accessory bar, and list continuation.
3. Attachments: the folder, photos and files, thumbnails, the send order, lazy fetching, and the Wi-Fi switch.
4. Capture from outside: the share extension, the control and widget, the App Shortcut, and the menu bar panel on macOS.
5. Looking back: the month picker, the year view, the on-device model as [on-device-model.md](on-device-model.md) proposes, and then reflection.

## Open questions

- Whether the marks other than image lines and links are hidden off the current line in a later version, or stay faint for good.
- Whether a short video gets a thumbnail or stays a file.
- Whether the menu bar panel on macOS is a separate process or a window of the main app.
- What the year view shows beyond a mark per day.
