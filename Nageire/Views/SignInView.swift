import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The first screen, with the code screen pushed over it while GitHub waits for the code to be entered.
struct SignInView: View {
    @State private var model: SignInModel
    @State private var signInTask: Task<Void, Never>?
    @State private var didCopy = false
    @Environment(\.openURL) private var openURL

    init(model: SignInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        front
            .signInScreen()
            .navigationDestination(item: awaitingCode) { code in
                authorization(code)
                    .signInScreen()
            }
            .onDisappear { signInTask?.cancel() }
    }

    /// The code GitHub is waiting for, while it is. Going back sets it to nil, which ends the wait.
    private var awaitingCode: Binding<DeviceCode?> {
        Binding {
            if case .awaitingAuthorization(let code) = model.state { code } else { nil }
        } set: { code in
            if code == nil {
                signInTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var front: some View {
        switch model.state {
        case .idle, .requestingCode, .awaitingAuthorization:
            page(StepList(), buttonTitle: "Sign in with GitHub")
        case .failed(let failure):
            page(Text(message(for: failure)).multilineTextAlignment(.center), buttonTitle: "Try again")
        }
    }

    private func page(_ middle: some View, buttonTitle: LocalizedStringKey) -> some View {
        FitsOrScrolls {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(.appMark)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 132)
                    .accessibilityHidden(true)
                Text(verbatim: "Nageire")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)
                Text("Toss in your thoughts, arrange them later.")
                    .font(.subheadline)
                    .foregroundStyle(.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer(minLength: 40)
                middle
                Button {
                    didCopy = false
                    signInTask = Task { await model.signIn() }
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(model.state == .requestingCode)
                .padding(.top, 40)
            }
        }
    }

    private func authorization(_ code: DeviceCode) -> some View {
        FitsOrScrolls {
            VStack(spacing: 20) {
                StepList(current: 1)
                VStack(spacing: 12) {
                    DeviceCodeCard(code: code.userCode)
                    footnote("Pressing “Open GitHub” also puts the code on the clipboard.")
                }
                VStack(spacing: 10) {
                    Button {
                        copy(code.userCode)
                        openURL(code.verificationURL)
                    } label: {
                        Label("Open GitHub", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    // Stays for a person who opens GitHub on another device.
                    Button {
                        copy(code.userCode)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy code", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for authorization…")
                }
                .font(.footnote)
                .foregroundStyle(.ink2)
                Spacer(minLength: 20)
                // GitHub's device authorization page shows neither the app's logo nor its description,
                // so the user learns here what that page will ask for.
                footnote("GitHub will ask you to authorize Nageire. It can read and write only the repositories you install it on.")
            }
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.ink2)
            .multilineTextAlignment(.center)
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

private extension View {
    /// Paper to the edges, with the content at the gutter and no wider than a phone.
    func signInScreen() -> some View {
        padding(Spacing.gutter)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.ink)
            .background(.paper)
            #if os(macOS)
            .navigationTitle(Text(verbatim: "Nageire"))
            #endif
            .toolbarTitleDisplayMode(.inline)
    }
}

/// A layout that spreads over the height it is given, and scrolls at a text size where it does not fit.
private struct FitsOrScrolls<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The shadow of the primary button falls outside the content.
            .scrollClipDisabled()
        }
    }
}

#Preview("Sign in") {
    NavigationStack {
        SignInView(model: AppModel.sample(.signedOut).makeSignInModel())
    }
}

#Preview("Device code") {
    let model = AppModel.sample(.signedOut).makeSignInModel()
    NavigationStack {
        SignInView(model: model)
    }
    // The sample's GitHub never authorizes, so the screen stays on the code.
    .task { await model.signIn() }
}
