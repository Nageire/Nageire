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

### 3. One note, one file

Each note is a separate file. Two devices rarely edit the same file at the same time, so writing from several devices seldom produces conflicts.

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
- No Git implementation on the device. Notes are written, edited, and deleted through the GitHub REST API (Contents API), one file per request, and listed and read through the Git Trees and Blobs APIs. By principle 3 every note is a self-contained file, so no operation needs more than one file at a time.
- A note is the file `notes/YYYY/MM/<timestamp>-<suffix>.md`. The timestamp is the UTC time of writing, so that name order is writing order whatever time zone each device is in, and the suffix is four random hexadecimal digits, so that two devices writing in the same second produce different names. One directory per month keeps every directory far below the 1,000 entries the Contents API lists.
- A note starts with front matter holding `created`, the time of writing with its UTC offset, and once it has been edited `updated` as well. The UTC file name alone would lose whether a note was written in the morning or at night.
- A note can be edited and deleted in the app. Both take effect on the device at once and are sent afterwards like a new note, so neither waits for the network.
- An edit replaces the text and leaves the file name and the front matter as they are, apart from `updated`, the time of the last edit. A file without front matter, which the app did not write, is not given one.
- When a note was changed elsewhere before an edit or a deletion from this device arrives, the one that arrives last wins: an edit overwrites the other version or brings a deleted file back, and a deletion removes the file whatever it holds. The app shows no conflict. Git keeps the version that lost, and one person rarely changes the same note on two devices at once.
- The device's copy stays what the repository holds. An edit or a deletion not yet sent is laid over the copy when the list is shown, so a refresh does not undo it.
- An edit or a deletion not yet sent stays on the device through a sign-out, like a note not yet sent, and goes to the repository chosen next. In a different repository the edit creates the note there, and the deletion finds no file and ends.
- Deleting asks for confirmation every time. The app has no trash, and a deleted note comes back only from the Git history.
- Notes and changes to them are sent right after saving, and again when the app is opened or brought to the front. Nothing is sent while the app is closed.
- The list shows every note in the repository, not only those written on the device. The device keeps a copy, so the list and search work offline. The copy is brought up to date when the app is opened or brought to the front: the Git Trees API lists everything under `notes/` at once, and only files that are new or changed are fetched.
- The app opens on the list, newest note first, and writing is one tap away. Principle 4 puts writing at once before everything else; the list won that place because seeing what was last written is what most often prompts the next note. The cost is one tap, and no network wait is added to writing.
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
