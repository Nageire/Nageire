# Design brief for Claude Design

Paste the brief below into Claude Design to make the Nageire design system. Attach the complete logo in both appearances, `Nageire/Assets.xcassets/AppLogo.imageset/logo-light.svg` and `logo-dark.svg`, and give it the link to the canvas "Nageire UX Redesign". The layer files under `Nageire/AppIcon.icon/Assets/` (`vase.svg`, `flowers.svg`, and their dark versions) are the same drawing split for Icon Composer and are only worth attaching when the tool asks for the parts. The decisions the brief rests on are in [ux-redesign.md](ux-redesign.md) and [on-device-model.md](on-device-model.md).

Claude Design publishes its result as one HTML file that unpacks itself: a `__bundler/manifest` script holds the assets as gzip-compressed base64, and a `__bundler/template` script holds the page as a JSON string. The stylesheet with the tokens is the first `<style>` element of the template, and the component library and the screen kits are the assets whose first line names `preview/nageire.jsx` and `ui_kits/iphone/kit.jsx` or `ui_kits/macos/kit.jsx`. A session that can read the artifact decodes those with a few lines of Python, renders the kits in Chromium through Playwright, and refreshes `docs/design/` from them, which is how the files there were made. A publish that fails for size means a font or a raster image was embedded; the brief's SIZE section says what to send back.

```text
Make a design system for Nageire, a notes app for iOS 26 and macOS 26 built in SwiftUI. Deliver tokens, type, components, and example screens, each in light and dark. The system has to sit on Apple's standard controls: it restyles them, it does not replace them.

WHAT NAGEIRE IS
Nageire (投げ入れ) is a style of ikebana in which flowers are placed in a tall vase as if tossed in, without a fixed form. The app works the same way: you toss in a thought with no folder, tag, or title to choose, and give it shape later. Each note is a Markdown file in the user's own GitHub repository. There is no server. A small language model on the device quietly finds related notes and suggests a title now and then; later, a language model of the user's choosing reads across the notes and helps them look back. Tagline: "Toss in your thoughts, arrange them later." / 「思いついたら投げ入れて、整えるのはあとで。」

Two moments drive every decision. Tossing in wants the fewest decisions and the shortest path to a text field. Looking back wants what was tossed in to be found, read, and recognized.

THE BRAND, WHICH STAYS AS IT IS
- Logo (attached): a black vase with two branches and two five-petal vermilion flowers on cream. Do not redraw it. You may derive one custom glyph from the vase for the primary action.
- Brand colors: paper #F2EDE3, ink #2A2825, vermilion #C1563F. Dark: paper #1F1D1B, ink #F2EDE3, vermilion #D86A52.
- Name set in the system font, bold. No wordmark.

PRINCIPLES FOR THE INTERFACE
1. Nothing is asked at the moment of writing. No title field, no folder, no tag.
2. The file is what you see. Markdown stays Markdown in the editor and is styled in place; syntax marks stay visible in a faint color. No WYSIWYG, no preview mode.
3. Paper, ink, vermilion, and nothing else. Vermilion is reserved for the one primary action ("投げ入れる", Toss in) and for marks that ask for attention.
4. The system first. SF Symbols, Dynamic Type, iOS 26 glass toolbars with the accent tint, standard lists and forms. Custom drawing is limited to the editor.
5. Quiet. Hairlines, not shadows; shadows only on what floats. No gradients, no illustrations beyond one empty-state drawing, no congratulation, no exclamation marks.
6. The on-device model is quietly there. Nothing it produces gets a badge, a sparkle, or the word AI. What is derived from the user's text looks derived (ink-2, italic) and becomes the user's own only by a tap. The one sentence that explains it is plain: it runs on this device and sends nothing.

TOKENS TO PRODUCE
Colors. Start from these and keep every text pairing at 4.5:1 or better (3:1 at 24 px and above):
  light: paper #F2EDE3, paper-raised #FAF7F1, paper-sunken #E8E1D4, hairline #DAD2C3, ink #2A2825, ink-2 #655F56, ink-faint #B9B1A3 (Markdown marks and placeholders only), accent #B8503A (fills), accent-text #9E3F2B, accent-wash #F1D9D1, on-accent #FAF7F1 (the label on an accent fill)
  dark: paper #1F1D1B, paper-raised #2A2724, paper-sunken #161412, hairline #3A3631, ink #EDE7DB, ink-2 #A9A194, ink-faint #5E5850, accent #D86A52, accent-text #E07A61, accent-wash #3B2620, on-accent #1F1D1B (fills carry the dark paper, not white)
Type. UI: SF Pro / Hiragino Sans, Dynamic Type sizes (Large Title 34, Title 2 22, Body 17, Subheadline 15, Footnote 13, Caption 12). Note body: 17 with 1.65 leading for Japanese; an optional serif variant (Hiragino Mincho ProN / New York) for the body only. Headings inside a note: 24 / 20 / 17 semibold. Mono: SF Mono 15. A derived style: ink-2 italic, used for a tentative title and nothing else.
Spacing. A 4-point grid. Screen gutter 20 on iPhone, 24 on macOS. Row padding 12 vertical.
Radius. 10 for inputs and thumbnails, 14 for cards, 20 for sheets, pill for buttons.
Elevation. Hairline for every division. One soft warm shadow for the floating bottom bar, the primary button, sheets, and the undo bar.
Motion. One signature moment: a tossed note's sheet goes down and the new row settles in at the top of the list. Everything else is the system's.

COMPONENTS
- Primary button (pill, accent fill, vase glyph + "投げ入れる"); secondary (hairline outline on paper-raised); destructive text button (accent-text).
- Bottom bar for iPhone: a glass pill holding the search field and the primary button.
- Note row: display title (17 semibold), up to two lines of excerpt (15, ink-2), meta line (13, ink-2: time, attachment count, unsent mark). Hairline between rows, inset to the gutter. Variant: the title is tentative, set in the derived style (ink-2 italic), with the excerpt beneath.
- Day header (13 semibold, ink-2): 今日 / 昨日 / 10月1日 水曜日.
- Unsent mark: a hollow circle with "未送信". Sent: nothing, or a small check in the note header.
- Banner for a refused write (accent-wash, accent-text), shown only when GitHub refuses.
- Undo bar: a floating pill at the bottom, paper-raised, "削除しました" on the left and "取り消す" in accent-text on the right, visible for ten seconds. It replaces the confirmation dialog.
- Editor styles: H1/H2/H3 with faint "#" marks, bold and italic with faint "*" marks, list items with aligned faint "-", task items as tappable checkboxes (accent when checked, strike-through text), links in accent-text with a hairline underline, an image shown as a rounded thumbnail under its line with a small caption (file name, size).
- Note header: date line (13, ink-2: written, edited, sent). Variant: a tentative title in the derived style with a small text button "見出しにする" beside it.
- Related section, below the note's text: the label "関連" (13 semibold, ink-2), up to five rows, each a note's title (15) with a short reason beneath (13, ink-2: 同じ歯医者の話 / 先月の稽古の続き), and a last line in footnote size, "この端末の中で探しました". The section is absent when there is nothing related.
- Keyboard accessory bar (iOS): photo, camera, file | heading, list, checklist, bold, link | lower keyboard.
- Settings rows: grouped cards on paper-raised with hairlines; segmented control; switch in accent. One section holds a single switch, "関連するメモと見出しの提案", with the sentence "この端末の Apple Intelligence で動きます。メモは外に送りません。" beneath; its unavailable state is the sentence "この端末では使えません。Apple Intelligence が必要です。" with no switch.
- Sign-in step list (numbered ink circles) and the device-code card (mono, 38, letter-spaced).
- Empty state: one line drawing of an empty vase, a title, two lines of text.
- macOS: sidebar on a slightly deeper paper, selected row in accent-wash, toolbar with the primary pill and ⌘N hint, a floating quick-entry panel (560×340).

SCREENS TO SHOW (iPhone 390×844, macOS 1280×800), in Japanese, light and dark
1. Sign-in: logo, name, tagline, the three steps (GitHub でコードを入力する / Nageire を認可する / メモを保存するリポジトリにインストールする), "GitHub でサインイン".
2. Device code: step indicator, the code card, "コードをコピー", "GitHub を開く", "認可を待っています…".
3. Empty stream: "まだ何もありません" and the bottom bar.
4. Stream: day groups, rows with titles and excerpts, one row unsent, one with attachments, one with a tentative title in the derived style, the bottom bar.
5. Stream right after a deletion: the same list with the undo bar at the bottom.
6. Toss-in sheet: timestamp label, close, "投げ入れる", a note being typed with a heading, a checklist, and a photo thumbnail, the accessory bar, the keyboard.
7. Note: back, share, menu; date and edited line; styled Markdown with a photo; the related section with three rows and its last line; no keyboard.
8. Note with a tentative title: the header variant with "見出しにする", for a note that has no heading.
9. Settings: アカウント / リポジトリ / 同期 / 書く / 関連するメモと見出しの提案 / 振り返る (準備中).
10. macOS main window: sidebar list beside a note with its related section; and the quick-entry panel.

COPY (Japanese first, English second)
投げ入れる Toss in · 新しいメモ New note · 未送信 Unsent · 送信済み Sent · 振り返る Look back · 設定 Settings · 検索 Search · 削除しました 取り消す Deleted, Undo · 関連 Related · この端末の中で探しました Found on this device · 見出しにする Use as heading · 関連するメモと見出しの提案 Related notes and title suggestions · この端末の Apple Intelligence で動きます。メモは外に送りません。 Runs with Apple Intelligence on this device. Notes never leave it. · まだ何もありません Nothing here yet · 思いついたことを、そのまま投げ入れてください。整えるのはあとでいい。

DO NOT
- No tabs, no folders, no tags, no title field. Topics the model finds are never shown on a note.
- No sparkle icons, no "AI" or "スマート" wording, no badges on anything the model produced.
- No gradients, no glassmorphism beyond the system's toolbars, no emoji, no stock photography.
- No colors beyond the tokens. No blue. Success needs no color; absence of the unsent mark is success.
- No confirmation dialog for deletion; the undo bar is the guard.
- No fake status bars in the mockups.
- Do not invent features; the screens above are the whole app for now.

SIZE
The published bundle must stay under 16 MB, and a Japanese font alone can take several MB per weight, so:
- Embed no font file. Use the system stack (-apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif) and, if a web font is needed to render Japanese, one Google Fonts <link> for Noto Sans JP. Never a data: URI or an @font-face with embedded data.
- Use no raster image anywhere. A photo thumbnail is a placeholder drawn in CSS or inline SVG on paper-sunken. The logo is the attached SVG, included once as a shared asset, not duplicated per screen as a data URI.
- Share every asset between light and dark, and between screens.
- If the bundle is still over the limit, publish the design system (tokens, type, components) first and the ten screens as a second artifact that uses it.

OUTPUT
A Design System with tokens.json (light and dark), the type scale, every component above with its states, and the ten screens. Note any token you changed from the starting values and why, and the final bundle size.
```
