import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SignInView: View {
    @State private var model: SignInModel
    @State private var signInTask: Task<Void, Never>?
    @State private var didCopy = false
    @Environment(\.openURL) private var openURL

    init(model: SignInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 24) {
            switch model.state {
            case .idle:
                introduction
                signInButton("Sign in with GitHub")
            case .requestingCode:
                ProgressView()
            case .awaitingAuthorization(let code):
                authorization(code)
            case .failed(let failure):
                Text(message(for: failure))
                    .multilineTextAlignment(.center)
                signInButton("Try again")
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { signInTask?.cancel() }
    }

    private var introduction: some View {
        VStack(spacing: 8) {
            Image(.appLogo)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityHidden(true)
                .padding(.bottom, 16)
            Text(verbatim: "Nageire")
                .font(.largeTitle.bold())
            Text("Toss in your thoughts, arrange them later.")
                .foregroundStyle(.secondary)
            steps
                .padding(.top, 24)
        }
        .multilineTextAlignment(.center)
    }

    // GitHub's pages do not say that installing follows authorizing, so the whole path is
    // laid out before it starts and the empty repository list after sign-in is expected.
    private var steps: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            step(1, "Enter a code on GitHub")
            step(2, "Authorize Nageire")
            step(3, "Install it on the repository for your notes")
        }
        .multilineTextAlignment(.leading)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        GridRow {
            Text(number, format: .number)
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func signInButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            didCopy = false
            signInTask = Task { await model.signIn() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func authorization(_ code: DeviceCode) -> some View {
        Text("Enter this code on GitHub")
            .font(.headline)
        Text(verbatim: code.userCode)
            .font(.system(.largeTitle, design: .monospaced).bold())
            .textSelection(.enabled)
        Button(didCopy ? "Copied" : "Copy code", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
            copy(code.userCode)
            didCopy = true
        }
        Button("Open GitHub") { openURL(code.verificationURL) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        HStack(spacing: 8) {
            ProgressView()
            Text("Waiting for authorization…")
                .foregroundStyle(.secondary)
        }
        // GitHub's device authorization page shows neither the app's logo nor its description,
        // so the user learns here what that page will ask for.
        Text("GitHub will ask you to authorize Nageire. It can read and write only the repositories you install it on.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        Button("Cancel", role: .cancel) { signInTask?.cancel() }
    }

    private func message(for failure: SignInModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .expired: "The code expired. Start again."
        case .denied: "Authorization was denied on GitHub."
        case .network: "Could not reach GitHub. Check your connection and try again."
        case .other: "Sign-in failed. Try again."
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
