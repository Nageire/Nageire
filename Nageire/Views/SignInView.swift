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

    init(oauth: GitHubOAuth, onAuthorized: @escaping (TokenGrant) throws -> Void) {
        _model = State(initialValue: SignInModel(flow: DeviceFlow(oauth: oauth), onAuthorized: onAuthorized))
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
            Text(verbatim: "Nageire")
                .font(.largeTitle.bold())
            Text("Toss in your thoughts, arrange them later.")
                .foregroundStyle(.secondary)
            Text("Notes are stored in a GitHub repository you choose.")
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
        .multilineTextAlignment(.center)
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
