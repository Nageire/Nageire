# Nageire concept

Nageire is a notes app for iOS and macOS. This document records what the app does and why it does it that way, so that later design decisions can be checked against it. Anything not yet settled is listed under "Open questions" at the end and moves into the body once decided.

## The name

The name comes from nageire (投入), a style of ikebana in which flowers are placed in a tall vase as if tossed in, without a fixed form. It describes how the app treats notes: you toss them in without thinking about hierarchy or categories, and give them shape later. The tagline is "Toss in your thoughts, arrange them later."

## The problem

You want to write down a diary entry or a passing thought right away, with no sorting. At the same time, you want to look back across what has piled up: a career retrospective, a history of doctor visits, questions that span months and topics.

These two wishes do not coexist at the moment of writing. If the app demands a category before you write, deciding on one becomes a chore and you stop writing. So nothing is sorted at input time. Sorting and organizing happen later, and a language model does that work. Input is only tossing in; shape is given when you read back.

## Principles

### 1. The data is the asset, the app is replaceable

Notes are stored as Markdown files in the user's own GitHub repository. If you stop using the app, the data stays as it is and any other tool can read it.

Notes kept over years outlive the app that wrote them. To avoid data that becomes unreadable because of the app's own choices, the format is plain text a person can read, and the storage is under the user's control.

### 2. No organizing at input time

The app does not ask for folders or tags. A file is named by the time it was written, and the directory it goes into follows from that time, so nothing about where a note lives is asked of the user.

Asking for a category adds thinking before writing, and that much less gets written. The absence of structure is not a shortcoming; it is the purpose described in "The problem".

### 3. One note, one file and its folder

Each note is a separate file, and the photos and other files it holds are in a folder beside it, named like it. Two devices rarely edit the same file at the same time, so writing from several devices seldom produces conflicts. A note and its folder are one unit to delete or to move, and nothing about the layout has to be known to find a note's files.

### 4. Local first

A note is saved on the device the moment it is written. Syncing to GitHub happens in the background. Being able to open the app and write immediately comes before everything else.

Waiting on the network at the moment you want to write is enough to lose the urge. Never blocking on a save, and writing while offline, both follow from this principle.

### 5. No server of our own

Data lives only on the device and in the user's GitHub repository. The developer collects nothing.

A diary gathers personal content. With no server on the developer's side, there is no data in the developer's custody at all, and the user has no leak or shutdown to worry about.

### 6. Reflection is done by a language model

Reading across the accumulated notes and answering a question is the job of a language model. Before note content is sent to an external model, the app tells the user and asks for consent. The API key for the model is the user's own.

By principle 5 the content is already out of the developer's hands. The decision to send it to a model is left to the user as well. Using the user's own API key keeps both the cost and the destination of the data with the user.

## Technical decisions

- A SwiftUI multiplatform app for iOS and macOS. Input happens mostly on the phone, so iOS is built out first.
- No Git implementation on the device. Notes are written, edited, and deleted through the GitHub REST API (Contents API), one file per request, and listed and read through the Git Trees and Blobs APIs. By principle 3 every note and every file it holds is self-contained, so no request needs more than one file.
- A note is the file `notes/YYYY/MM/<timestamp>-<suffix>.md`. The timestamp is the UTC time of writing, so that name order is writing order whatever time zone each device is in, and the suffix is four random hexadecimal digits, so that two devices writing in the same second produce different names. One directory per month keeps every directory far below the 1,000 entries the Contents API lists.
- A note's files are in the folder `notes/YYYY/MM/<timestamp>-<suffix>/`, the note's name without `.md`. A file keeps its own name with the characters GitHub cannot take replaced, and a second file of the same name gets a counter. The note links each one relatively, `![](<timestamp>-<suffix>/IMG_0421.jpeg)` for an image and `[scan.pdf](<timestamp>-<suffix>/scan.pdf)` for any other file, so GitHub's file view shows the image and opens the file. A folder under a top-level `attachments/` was the alternative and lost on longer links and a note that is no longer one unit.
- A photo is kept and sent as JPEG with its long side reduced to 2048 pixels, which turns the 3 to 5 MB a camera produces into a few hundred kilobytes; a diary with a photo a day stays under the 1 GB GitHub recommends for years. A setting offers 4096 pixels and the original, which is the photo's own pixels as JPEG, since GitHub's file view does not show HEIC. An image that comes in as a file is reduced the same way, and one with no name of its own, as a screenshot copied, is named like a photo from the camera. A GIF and an SVG are kept as they are. A photo loses the place it was taken before it is kept, since the repository may be public; the time and the camera stay.
- Any other file is kept as it is. Above 25 MB the app warns before keeping it; above 100 MB the Contents API refuses, and the app says so instead of trying. Git LFS is not reachable through the Contents API and is not used.
- A new note has no folder until it is saved, so the draft's first file gives it the name of the note it becomes, kept with the draft, and the note is dated by that file rather than by the save. A draft emptied lets go of its name and its files.
- The outbox sends a note's files before the note, one commit each, so the note on GitHub never names a file that is not there yet. A file still waiting is counted among the unsent; a draft's files are not, since no send can move them until the draft is saved. A switch sends photos, and the notes that link them, only on Wi-Fi; it is off by default.
- A file no line of its note names any more is removed at the next send of that note. A file another device sent is removed this way only when the copy of the note GitHub held before the edit linked it, since a file no copy has linked yet may belong to a note still on its way from that device.
- A refresh lists the files of other devices; one is fetched only when its note is opened, whatever the network, and kept afterwards. Thumbnails are made on the device. The listing is kept in memory, since every launch refreshes.
- A note starts with front matter holding `created`, the time of writing with its UTC offset, and once it has been edited `updated` as well. The UTC file name alone would lose whether a note was written in the morning or at night.
- A note can be edited and deleted in the app. Both take effect on the device at once and are sent afterwards like a new note, so neither waits for the network.
- An edit replaces the text and leaves the file name and the front matter as they are, apart from `updated`, the time of the last edit. A file without front matter, which the app did not write, is not given one.
- When a note was changed elsewhere before an edit or a deletion from this device arrives, the one that arrives last wins: an edit overwrites the other version or brings a deleted file back, and a deletion removes the file whatever it holds. The app shows no conflict. Git keeps the version that lost, and one person rarely changes the same note on two devices at once.
- The device's copy stays what the repository holds. An edit or a deletion not yet sent is laid over the copy when the list is shown, so a refresh does not undo it.
- An edit or a deletion not yet sent stays on the device through a sign-out, like a note not yet sent, and goes to the repository chosen next. In a different repository the edit creates the note there, and the deletion finds no file and ends.
- Deleting a note, by swipe or from its menu, removes the row at once and shows 削除しました with 取り消す in a bar at the bottom for ten seconds; the deletion is sent when the bar goes, and the bar waits while the app is not in front. Command-Z on macOS and the shake on iOS undo it too, through the system's undo manager. A confirmation was the rule before and was turned down: it is answered without being read from the third time on, while an undo asks nothing and still protects. The app has no trash, and a deleted note comes back only from the Git history.
- A new note is sent right after saving, and a change to a note when the editor's pause ends (The screens below); both are sent again when the app is opened or brought to the front. Nothing is sent while the app is closed.
- The list shows every note in the repository, not only those written on the device. The device keeps a copy, so the list and search work offline. The copy is brought up to date when the app is opened or brought to the front: the Git Trees API lists everything under `notes/` at once, and only files that are new or changed are fetched.
- The app opens on the stream: every note, newest first, grouped by day under 今日, 昨日, and then the date with its weekday. Writing is one tap away. Principle 4 puts writing at once before everything else; the list won that place because seeing what was last written is what most often prompts the next note. The cost is one tap, and no network wait is added to writing.
- In a wide window, on macOS and iPad, the list and one note sit side by side, and a new note is written in the place where a note is read. With no note selected that place is the text field, so there writing is at hand as soon as the window opens. A compact-width window, on iPhone or a narrowed iPad window, keeps the single column and writes in a sheet.
- Search runs on the device over the text of the notes.
- A device belongs to one person. Notes not yet sent stay on the device through a sign-out and go to the repository chosen after the next sign-in, whoever signs in.
- Authentication uses a GitHub App with the device flow. Permission is limited to the single repository the user picks for notes, so the app can read and write nothing but the place where notes live. Tokens are stored in the Keychain.
- User tokens expire after eight hours and are renewed with the refresh token. When renewal fails, the app returns to the sign-in screen.
- The destination repository is chosen from the repositories where the user has installed the GitHub App. The app does not create repositories.
- GitHub's device authorization page shows neither the app's logo nor its description, and installing the GitHub App is a separate page that GitHub does not lead to. The app's own screens carry the explanation: the first screen lists the three steps (enter a code, authorize, install on the repository for notes), the code screen says what GitHub will ask for, and the repository list, while empty, says how to install. GitHub opens in the browser, where the user is already signed in, and the repository list is read again when the app comes back to the front.
- The app icon is one Icon Composer file, `AppIcon.icon`, in three layers: the background, the vase with its branches, and the flowers. The system renders the light, dark, tinted, and clear appearances from it.
- No repository name or token is hard-coded. Sign-in and the choice of destination repository are screens in the app. The GitHub App's client ID is public, not a token, and ships with the app.
- The minimum OS is the current release, iOS 27 and macOS 27.

## The screens

The look and the words were settled in the redesign ([ux-redesign.md](ux-redesign.md) holds the reasons) and are built phase by phase. What follows is the decisions in force; the design they match is in [design-reference.md](design-reference.md).

- A note has no title field. The list and the note's header show a display title derived from the text: the first non-blank line without its `# ` when it is a heading, otherwise that line cut at the end of its first sentence or at 40 characters, whichever comes first, with the Markdown marks taken out. A note whose only line is an image, or a link to one of its files, is called by the file's name. The file name stays the timestamp, and nothing goes into the front matter for it.
- The colors are paper, ink, and vermilion, the palette of the icon, with the token values in `docs/design/tokens.css` and the color sets of the same names in the asset catalog. Vermilion fills one control per screen, the primary action, and colors the marks that ask for attention; a sent note carries no mark. Surfaces are divided by hairlines, and a shadow belongs only to what floats.
- The type is the system's, following Dynamic Type. The body of a note is 17 points with a leading of 1.65, and a setting puts it in a serif and leaves the rest of the app in sans. Icons are SF Symbols, with one custom glyph, the vase of the logo, for a new note.
- A row of the stream shows the display title, up to two lines of excerpt, the time, the number of attachments, and 未送信 with a hollow circle while the note is not on GitHub. A sent note shows nothing. The footer that counted unsent notes is gone; a banner above the stream appears only when GitHub refused a write, with a link to Settings, and a transient failure shows nothing.
- On iPhone a bar at the bottom holds the search field and the button for a new note, the vase alone, named 新しいメモ. The button opens a sheet; closing it keeps the draft, and while a draft waits the stream shows it as a row at its top, 書きかけ over the first line, which opens the sheet too. 完了 keeps the note and sends it. Search filters the stream as the query is typed, and a day header stays above its matches. Settings sit behind the button at the top right.
- A row opens the note full screen under a line with when it was written, when it was edited, and whether GitHub has it, with Share and a menu holding GitHub で開く and 削除. GitHub で開く is disabled while the page on GitHub does not show the note as it is on the device.
- Reading and editing are one surface. Opening a note does not raise the keyboard; a tap into the text does. There is no Edit, Save, or Cancel: what is typed is on the device as soon as the typing pauses, and GitHub gets one commit when the note is closed, when another is selected, when the app leaves the front, or after thirty seconds without a change, whichever comes first. A note emptied in the editor is not saved as empty; it keeps its last text, and deleting is the menu's. A new note keeps its button, 完了, which sends it as one commit.
- Markdown stays the text and is styled in place: headings at their sizes, emphasis and code in their fonts, a list marker in its column, a task as a box that toggles with a tap, a link in the accent, and an image as a thumbnail under its line. The marks stay in sight, faint, with two exceptions: an image line is its thumbnail alone and a link its text alone while the caret is elsewhere, and a note that was only opened has no caret. Return inside a list continues it, with an open box after a task and the next number after a numbered item, and Return on an empty item ends it. On iOS a bar above the keyboard holds heading, list, checklist, bold, and link, and a key that lowers the keyboard: heading puts `# ` on the first line, wherever the caret is, and is the whole of adding a title, and list and checklist act on the caret's line; on macOS the Format menu holds 太字, イタリック, and リンクを追加 with Command-B, Command-I, and Command-K.
- An image's thumbnail carries the file's name and size, and is the frame alone until the file is on the device. A tap on a thumbnail shows the file full screen with the system's Quick Look, at any time; a line that links any other file opens it the same way, on iOS with a tap while the note is read and on macOS with a Command-click, since there a click places the caret. On iOS the bar above the keyboard begins with three keys, the library, the camera, and the files; on macOS the Format menu holds 写真を追加… at Shift-Command-I and ファイルを追加… at Shift-Command-A. A file pasted, or dropped on iPad and macOS, comes in the same way, and the lines of several files go in at the caret together.
- Settings has the groups アカウント, リポジトリ, 同期 with the count of unsent items, 今すぐ送信, the time of the last send, 写真は Wi-Fi 接続時のみ送信, and 写真のサイズ (標準, 大, 元のサイズ), 書く with the serif choice, and the on-device model's sentence. 振り返る is 準備中 until it ships.
- In a wide window the list stays beside the note, Command-N writes in the detail column, search is in the sidebar, and the selected row is tinted with the accent wash.
- Sign-in shows the mark, the name, the tagline, and the three steps before the first one starts; the code screen shows the steps again with the first one current, the code on a card, GitHub を開く, which also puts the code on the clipboard, and コードをコピー for a person who opens GitHub on another device.
- The words: メモ everywhere, never ノート; 新しいメモ for the button and the command; 完了 for the sheet's action; 書きかけ for the draft's row; 未送信 and 送信済み; 削除しました and 取り消す, the system's word for Undo. The voice is plain and short, with no congratulation and no exclamation mark, and the buttons borrow the system's words. The app's own word, 投げ入れる, stays in the name and the tagline and is on no button.

## Roadmap

Build up from the smallest thing that works.

1. GitHub sign-in through the device flow and the choice of the destination repository. Sign-in comes first so that no interim way of supplying a token is ever written.
2. Writing a note, saving it on the device, and sending it to GitHub, and nothing else.
3. A list of notes and search.
4. Layout adjustments for macOS.
5. Editing and deleting notes.
6. The finished sign-in experience and app icon.
7. Distribution through TestFlight, then release on the App Store.

Reflection with a language model is set aside for now and has no place in this order yet.

## Open questions

- Whether notes are also sent while the app is closed.
- How much of the reflection feature lives inside the app. Running an external tool against the repository would also work.
- Whether reflection results are written back to the repository as derived files.
- The license.
