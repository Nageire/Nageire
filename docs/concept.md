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

The app does not ask for folders or tags. Files are named by timestamp and placed flat.

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
- No Git implementation on the device. Files are read and written through the GitHub REST API (Contents API). By principle 3 every note is a self-contained file, so reading and writing one file at a time covers saving and opening a note.
- Authentication uses a GitHub App with the device flow. Permission is limited to the single repository the user picks for notes, so the app can read and write nothing but the place where notes live. Tokens are stored in the Keychain.
- User tokens expire after eight hours and are renewed with the refresh token. When renewal fails, the app returns to the sign-in screen.
- The destination repository is chosen from the repositories where the user has installed the GitHub App. The app does not create repositories.
- No repository name or token is hard-coded. Sign-in and the choice of destination repository are screens in the app. The GitHub App's client ID is public, not a token, and ships with the app.
- The minimum OS is the current release, iOS 26 and macOS 26.

## Roadmap

Build up from the smallest thing that works.

1. GitHub sign-in through the device flow and the choice of the destination repository. Sign-in comes first so that no interim way of supplying a token is ever written.
2. Writing a note, saving it on the device, and sending it to GitHub, and nothing else.
3. A list of notes and search.
4. Layout adjustments for macOS.
5. Reflection with a language model.
6. The finished sign-in experience and app icon. GitHub's device authorization page shows neither the app's logo nor its description, so the app's own screens carry the explanation of what that page will ask for. The icon moves to layered artwork so that the system can render its light, dark, and tinted appearances.
7. Distribution through TestFlight, then release on the App Store.

## Open questions

- The exact file name and front matter format for a note. Two devices can produce the same timestamp for different notes, so the name needs more than the bare timestamp or a rule for the collision.
- How notes are enumerated once the directory holds more than the 1,000 entries the Contents API lists. The Git Trees API is one candidate.
- How much of the reflection feature lives inside the app. Running an external tool against the repository would also work.
- Whether reflection results are written back to the repository as derived files.
- The license.
