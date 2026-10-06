# Design reference

This is the design to match when the redesign is built, taken out of the Claude Design prototype so that no environment needs the artifact to work from. The prototype itself, interactive and in both appearances, is at https://claude.ai/artifact/Kjk517nBqpUeXyyhJ3UsVY. What this document and its folder hold is enough without it:

- [design/tokens.css](design/tokens.css) is the prototype's stylesheet verbatim: colors, type, spacing, radii, shadows, and motion as CSS custom properties.
- [design/iphone-light.png](design/iphone-light.png), [design/iphone-dark.png](design/iphone-dark.png), [design/mac-light.png](design/mac-light.png), and [design/mac-dark.png](design/mac-dark.png) are the eleven screens rendered from the prototype, to compare a build against.
- This document carries what the stylesheet does not: the measurements of each component, the composition of each screen, and how both map onto SwiftUI.

The decisions behind the design are in [ux-redesign.md](ux-redesign.md) and [on-device-model.md](on-device-model.md). This document does not repeat them, and when the two disagree the decision documents win.

## The five things to keep

1. Nothing is asked at the moment of writing. No title field, no folder, no tag, no dialog before the text field.
2. The file is what you see. Markdown stays Markdown in the editor and is styled in place. The syntax marks stay visible in ink-faint, except that an image line shows only its thumbnail and a link only its text while the caret is elsewhere.
3. Paper, ink, vermilion, and nothing else. Vermilion fills one control per screen, the primary action, and colors the few marks that ask for attention. Success has no color: a note that is sent carries no mark.
4. The system first. SF Symbols, Dynamic Type, the standard list, form, sheet, and toolbar, the glass toolbars of iOS 26. The one custom view is the editor.
5. Quiet. Hairlines divide; a shadow belongs only to what floats. What the on-device model produced looks derived (ink-2, italic) and becomes text only by a tap. No badge, no sparkle, no word for the model in the interface.

## Tokens

The values are in the stylesheet. The names below are what the Asset Catalog and the Swift code use for them.

| Color set | Light | Dark | Token |
| --- | --- | --- | --- |
| `Paper` | `#F2EDE3` | `#1F1D1B` | `--paper` |
| `PaperRaised` | `#FAF7F1` | `#2A2724` | `--paper-raised` |
| `PaperSunken` | `#E8E1D4` | `#161412` | `--paper-sunken` |
| `Hairline` | `#DAD2C3` | `#3A3631` | `--hairline` |
| `Ink` | `#2A2825` | `#EDE7DB` | `--ink` |
| `Ink2` | `#655F56` | `#A9A194` | `--ink-2` |
| `InkFaint` | `#B9B1A3` | `#5E5850` | `--ink-faint` |
| `AccentColor` | `#B8503A` | `#D86A52` | `--accent` |
| `AccentText` | `#9E3F2B` | `#E07A61` | `--accent-text` |
| `AccentWash` | `#F1D9D1` | `#3B2620` | `--accent-wash` |
| `OnAccent` | `#FAF7F1` | `#1F1D1B` | `--on-accent` |

The brand vermilion `#C1563F` and its dark `#D86A52` stay in the icon and the logo and are not used for controls. Where the stylesheet names a semantic alias (`--surface-card`, `--text-secondary`, `--fill-primary`), the Swift side names the same thing on an extension of `ShapeStyle` so that a view never spells a raw color.

The type is the system's at Dynamic Type sizes: large title 34/41 bold, title 2 22/28 bold, body 17/22, subheadline 15/20, footnote 13/18, caption 12/16. The body of a note is 17 with a leading of 1.65, in the sans by default and in the serif (Hiragino Mincho ProN, New York) by a setting that touches the note body only. Headings inside a note are 24, 20, and 17 at semibold with a leading of 1.35. Mono is SF Mono 15/22, and the device code is mono 38/46 at weight 500 with a tracking of 0.14 em. The derived style, for a tentative title and nothing else, is italic semibold in ink-2: body size in a row, 24 in a note header.

Spacing is a 4-point grid. The screen gutter is 20 on iPhone and 24 on macOS, a list row has 12 of vertical padding and 4 between its lines, every tap target is at least 44, a control is 44 high and 34 when compact, the macOS sidebar is 320 wide, and the quick-entry panel is 560 by 340. Radii are 10 for inputs and thumbnails, 14 for cards, 20 for sheets, and a pill for every button and bar. Divisions are hairlines of one physical pixel. The one shadow, `0 8px 24px rgba(42,40,37,0.14)` with `0 1px 2px rgba(42,40,37,0.06)`, belongs to the floating bottom bar, the primary button, sheets, the undo bar, and the macOS panels. Glass is `rgba(250,247,241,0.72)` behind a blur of 20 with a saturation of 1.1, which is what the system's toolbar material does on its own; the app draws it only where the system gives none.

Motion is one gesture. The toss sheet goes down in 320 ms on `cubic-bezier(0.32, 0.72, 0, 1)`; the new row settles in over 480 ms on `cubic-bezier(0.2, 0.8, 0.2, 1)` from 14 points above and from transparent, starting 120 ms after the sheet begins to leave. The undo bar stays ten seconds. Everything else is the system's.

## Components

Each item gives what the prototype draws; the measurements are in points.

- A primary button is a pill 44 high (34 compact) with 20 of horizontal padding (14 compact, and 16 or 12 on the side with a glyph), the accent fill, the on-accent label in semibold body (semibold subheadline compact), the vase glyph at 20 (16 compact), and the floating shadow. Inside the bottom bar it has no shadow of its own. A secondary button has the same shape on paper-raised with a hairline inset. A text button is the label alone in accent-text with 12 of padding (8 compact). A keyboard hint, such as ⌘N, follows a button at 10 of gap in footnote ink-2.
- The search field is 44 high (30 compact on macOS) with 14 of horizontal padding (10 compact), a magnifier at 18 (15 compact), the placeholder 検索, and the body size. On its own it is paper-sunken with the input radius; inside the bottom bar it is flat.
- The bottom bar is one glass pill with 6 of padding and 6 of gap holding the flat search field and the primary button, with the floating shadow and a hairline inset. It sits 20 from each side and 32 from the bottom.
- The undo bar is a pill 48 high on paper-raised with the floating shadow, 20 of padding on the left and 6 on the right, "削除しました" in subheadline, and "元に戻す" as a 36-high text button in semibold subheadline accent-text. It stacks 8 above the bottom bar and stays ten seconds.
- The banner for a refused write is a card on accent-wash with 12 by 16 of padding, a semibold subheadline line and a footnote line, both in accent-text.
- A day header is semibold footnote in ink-2 with 20 above and 6 below.
- The unsent mark is a 9-point hollow circle with a 1.5 stroke, then 未送信, in footnote ink-2 with 5 of gap. Sent is nothing, or a 12-point check in the note header.
- A note row is a grid with 4 of gap and 12 by gutter of padding: the title in semibold body on one line (the derived style when tentative), the excerpt in subheadline ink-2 on at most two lines, and a meta line in footnote ink-2 with 10 of gap holding the time, a paperclip at 14 with the count when there are attachments, and the unsent mark. A hairline inset to the gutter follows each row. The selected row on macOS is accent-wash with the input radius.
- The empty state is the vase outline 104 high in ink-2, 20 above a title 2 line and two subheadline lines in ink-2 at most 280 wide.
- The editor is a grid of lines with 2 of gap. A blank line is 55 percent of a body line. A heading is its marks in ink-faint, 10 of gap, then the text at the heading size, with 10 above (none when first) and 4 below. A list item has a 12-wide marker column with the "-" in ink-faint and 10 of gap. A task item adds a 22-point checkbox with a radius of 6, a 1.5 ink-2 border when open and the accent fill with an on-accent check at 15 when done, and done text is ink-2 and struck through. An image line is a thumbnail of 164 by 123 with the thumb radius and a caption in caption size ink-2 giving the file name and size; the raw `![name](path)` line appears in ink-faint only while the caret is on that line. A link is its text in accent-text with a hairline underline 3 below; the brackets and the address appear only while the caret is on the line. Bold, italic, and code keep their marks in ink-faint around the styled text. The caret is 2 by 22 in the accent.
- The note header is a footnote line in ink-2 reading "10月3日 9:12 · 昨日 18:40 に編集 · ✓", and, for a note without a heading, the tentative title in the derived header style with "見出しにする" beside it as a subheadline text button in accent-text, 12 apart.
- The related section is the label 関連 in semibold footnote ink-2, a hairline, then up to five rows of 10 vertical padding each ending in a hairline, with the other note's title in subheadline and the reason in footnote ink-2, and last the footnote line この端末の中で探しました in ink-2 with 10 above. The section is absent when there is nothing related.
- The accessory bar is 44 high on paper-raised with a hairline above and 8 of horizontal padding, holding 40 by 44 buttons with icons at 20 in three groups divided by 22-high hairlines: photo, camera, file; heading, list, checklist, bold, link; and the key that lowers the keyboard.
- A switch is 51 by 31: the accent fill when on, paper-sunken with a hairline inset when off, and a 27-point knob on paper-raised with a small shadow.
- A segmented control is paper-sunken with 2 of padding and a radius of 9, each segment 28 high with 14 of padding and a radius of 7 in semibold footnote, the chosen one on paper-raised with a hairline inset.
- A settings row is at least 44 high with 12 by 16 of padding and 12 of gap: the label in body, a value in body ink-2, an optional control, a chevron at 16 in ink-2, and a hairline below. A destructive row is in accent-text; a disabled one is at half opacity. A group has its header in semibold footnote ink-2 and its footer in footnote ink-2, each with 16 of horizontal padding, around a card on paper-raised with the card radius and a hairline inset.
- The step list has 16 of gap; each step is a 26-point circle followed by the text in body. A step still ahead or being done is ink-filled with the number in paper; a step done shows a check at 55 percent; a step after the current one is a hairline outline with the text in ink-2.
- The device-code card is a card with 24 by 20 of padding and the code centered in the mono style above.
- The navigation bar of a screen is 44 high under the status area with 16 of horizontal padding; its buttons are 34-point glass circles with a hairline inset and an icon at 18. A screen's large title sits under the bar in the large-title style with 20 of horizontal padding.
- On macOS the toolbar is 52 high on glass with a hairline below, holding the sidebar toggle at 32 by 28, the note's title in semibold subheadline, the share and menu buttons, and the compact primary button with its ⌘N hint. The sidebar is 320 wide on paper-sunken with a hairline on the right, 52 of header for the window controls, the compact search field on paper with a hairline inset, and rows with a gutter of 16. The note column centers its content at 680 wide with 28 above and 48 at the sides. The quick-entry panel is 560 by 340 on paper with the card radius, the floating shadow and a hairline inset: a header with the timestamp and a close button, the editor, and a footer with photo, file, heading, list, and checklist on the left and the compact primary button with its ⌘↩ hint on the right.

## Screens

- Sign-in: the logo mark at 132 without its background, the name in large title, the tagline in subheadline ink-2, the three steps, and the primary button "GitHub でサインイン" across the width.
- Device code: back, the three steps with the first current, the code card with the footnote 「GitHub を開く」を押すと、コードはクリップボードにも入ります。 under it, the primary "GitHub を開く" above the secondary "コードをコピー", a spinner with 認可を待っています…, and at the bottom the footnote that says what GitHub will ask for.
- Empty stream: the large title, the settings button, the empty state, and the bottom bar.
- Stream: day groups of rows, one row tentative, one unsent, one with attachments, and the bottom bar.
- Stream after a deletion: the same with the undo bar above the bottom bar.
- Toss sheet: the stream dimmed and scaled to 0.93 behind, the sheet from 24 below the top with the sheet radius and the floating shadow, a header with the close button on paper-sunken, the timestamp in footnote ink-2, and the compact primary "投げ入れる", then the editor with the caret, the accessory bar, and the keyboard.
- Note: back, share, and menu; the note header, the editor, the related section. The menu is a 220-wide glass card with GitHub で開く and, after a hairline, 削除 in accent-text.
- Note with a tentative title: the header variant with 見出しにする.
- Settings: アカウント (the GitHub login with a chevron, サインアウト), リポジトリ (the repository with a chevron), 同期 (未送信 with the count and the text button 今すぐ送信, 最後に送信 with the time), 書く (本文の書体 as a segmented control), a group without a header holding the switch 関連するメモと見出しの提案 with the sentence この端末の Apple Intelligence で動きます。メモは外に送りません。 as its footer, and 振り返る with 準備中 disabled. Without the model the footer reads この端末では使えません。Apple Intelligence が必要です。 and the switch is absent.
- macOS main window: the sidebar beside the note, the selected row in accent-wash, the related section under the note.
- macOS quick entry: the panel centered over the window in the prototype; in the app it opens from the menu bar over whatever is in front.

## From the design to SwiftUI

The building itself, with the shape of the code, the state, each component, and the previews, is in [ui-guide.md](ui-guide.md). In short:

- Colors go into `Assets.xcassets` as the color sets named above, each with an Any and a Dark appearance, and `AccentColor` is the accent. A `ShapeStyle` extension names them (`.paper`, `.ink2`, `.accentText`) and the semantic aliases, so that no view holds a hex value.
- Type uses the system text styles so that Dynamic Type works: `.largeTitle`, `.title2`, `.body`, `.subheadline`, `.footnote`, `.caption`. The note body is `.body` with the line spacing that gives 1.65, and the headings inside a note are scaled with `@ScaledMetric` from 24, 20, and 17. The derived style is `.italic()` on `.semibold`.
- The stream is a `List` in the plain style with a section per day and a custom row view; the hairline is the list's own separator inset to the gutter. On iOS 26 the search field goes into the bottom bar beside the primary button through the toolbar's bottom placement and the default search item; confirm the modifier names against the SDK before relying on them.
- The toss sheet is a `.sheet` with the system's grabber and the large detent; the undo bar is a view in a bottom safe-area inset, with the deletion queued when the ten seconds pass and `UndoManager` wired so that Command-Z and the shake gesture undo it too.
- The editor is the one custom view: a TextKit 2 text view in a `UIViewRepresentable` and an `NSViewRepresentable`, styling the Markdown it holds with attributes and placing the thumbnails as attachments. `TextEditor` with `AttributedString` can style text on iOS 26 but has no inline attachments, which is why it is not used.
- Settings is a `Form` in the grouped style with `LabeledContent`, `Toggle`, and a `Picker` in the segmented style; the footer sentence is the section's footer.
- On macOS the window is a `NavigationSplitView` with the sidebar at 320, search placed in the sidebar, and the primary button in the toolbar. The quick-entry panel is a separate window of the app opened by a global shortcut, which `MenuBarExtra` or an `NSPanel` provides.
- Icons are SF Symbols. The prototype stands in with Lucide glyphs under the SF names it maps from (`magnifyingglass`, `square.and.arrow.up`, `ellipsis`, `photo`, `camera`, `doc`, `textformat.size`, `list.bullet`, `checklist`, `bold`, `link`, `keyboard.chevron.compact.down`, `checkmark`, `doc.on.doc`, `arrow.up.right.square`, `gearshape`, `sidebar.left`, `trash`, `arrow.uturn.backward`); the app uses the SF Symbols themselves. The vase glyph is a custom symbol drawn from the logo's vase path.
