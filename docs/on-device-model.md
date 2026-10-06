# The on-device model

iOS 26 and macOS 26 carry a language model on the device, reachable through the Foundation Models framework. It costs nothing per call and sends nothing anywhere, so the consent that principle 6 requires before note content leaves the device does not apply to it. This document settles what Nageire does with it: three things, each quiet, none with a name of its own. It builds on [concept.md](concept.md) and [ux-redesign.md](ux-redesign.md), and its decisions move into concept.md once made.

## Rules

1. Nothing is asked at the moment of writing. The model reads a note after the toss, when the device has time.
2. The text is never changed. What the model produces is derived, looks derived, and becomes the person's own only by a tap.
3. Derived data is rebuilt, never synced. The device keeps it in a cache keyed by the note's blob SHA, and nothing of it goes into the repository.
4. A wrong answer is cheap: a suggestion ignored or a link not followed, never a changed file.
5. Without Apple Intelligence, the app is the app of today. There is no cloud fallback. The cloud is for reflection, with consent, as concept.md says.
6. The person is told, plainly and without a feature name, that the model runs on the device and sends nothing.

## Topics, for search

Each note gets one to five lowercase topics from the model's content-tagging use case, which is tuned for exactly this. They are never shown on a note, since a row of tags is the organizing the app refuses to ask for. They do two things. A search query matches a topic as well as the text, so "歯医者" finds a note that only says "右下の詰め物を替える". And they are the material for related notes.

## Related notes

Below the text of a note, a section "関連" lists up to five other notes, each with a short reason from the model, such as "同じ歯医者の話". Candidates come from shared topics and overlapping words, and the model ranks the short list and writes the reasons. The section is absent when nothing is related, so most short notes never show it. Its last line, in footnote size, reads "この端末の中で探しました". This is the one place the model's work is visible as such, and it is "arrange later" without a folder.

## Tentative titles

A note with no `# ` line whose first line is too long to serve as a title gets one of at most twenty characters. It is the one of the three that touches what the person reads as their own, so it is held to these rules.

- In the list it is set in ink-2 and italic, the style of what is not the person's words, with the excerpt beneath. A note whose first line already makes a title gets none.
- In the note, the header shows it with "見出しにする" beside it. The tap inserts it as the `# ` line, and from then on it is text. Nothing else ever makes it text.
- Editing the first line removes the suggestion, and it comes back only when the note changes again.
- It is never written to the file, never sent, and never searched.

It ships last, and only if the review below shows it right nine times in ten.

## What the person is told

Settings has a section with no name beyond what it does: a switch, "関連するメモと見出しの提案", and under it one sentence, "この端末の Apple Intelligence で動きます。メモは外に送りません。". On a device without the model the section reads "この端末では使えません。Apple Intelligence が必要です。" and the switch is absent. The README and the App Store description carry the same sentence. There is no onboarding screen, no badge, and no notification.

## Where it runs and what it costs

- The Foundation Models framework gives the content-tagging use case for topics and the default model, with guided generation into typed Swift values, for reasons and titles. A session's budget is small and is read from the model at run time, through the context size and the token count iOS 26.4 added, rather than fixed in code; it was 4096 tokens, prompt and answer together, on the first release. A long note is sent paragraph by paragraph within it.
- A note is read right after the toss while the app is in front, which takes a second or two. A backlog, after the first install or a large import, runs in the background on power, each note once per SHA.
- The model runs only where Apple Intelligence runs, with it switched on and a supported language. The app reads its availability at launch rather than keeping a list of devices.
- Before each of the three ships, the model is run over a fixed set of thirty real notes and the output is read by a person. A small model is wrong sometimes, and the question is whether its wrong answers are cheap, as rule 4 wants.

## Order

1. Topics and search by topic.
2. Related notes.
3. Tentative titles, if the review passes.

## Not done

Digests, threads, extracted dates and tasks, text in photos, questions answered on the device, and emotions were considered and left out. Each is useful on its own, and together they would make the model a feature rather than something that is quietly there. Reflection stays where concept.md puts it: a language model of the person's choosing, run only with consent.
