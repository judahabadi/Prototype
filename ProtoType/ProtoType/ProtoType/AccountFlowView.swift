import AuthenticationServices
import SwiftUI

/// Create Account / Sign In screens from the onboarding design.
/// Sign in with Apple only (no server); skipping is allowed because the
/// keyboard works without an account.
struct AccountFlowView: View {
    let onComplete: () -> Void
    let onBack: () -> Void

    private enum Mode { case create, signIn }
    @State private var mode: Mode = .create
    @State private var showPrivacyPolicy = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            landing(creating: mode == .create)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Create account / Sign in landing

    private func landing(creating: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                BrandWordmark(markSize: 40, fontSize: 40)
                Spacer().frame(height: 22)
                Text(creating ? "Create your account" : "Welcome back")
                    .font(.system(size: 30, weight: .bold))
                Text(creating
                     ? "Save your languages and sync them across your devices with iCloud."
                     : "Sign in to restore your languages on this device.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .frame(minHeight: 42, alignment: .top)
            }

            Spacer()

            VStack(spacing: 12) {
                signInWithAppleButton

                Button("Continue without an account", action: onComplete)
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)

                legalText

                HStack(spacing: 4) {
                    Text(creating ? "Already have an account?" : "New to ProtoType?")
                        .foregroundStyle(.secondary)
                    Button(creating ? "Sign In" : "Create Account") {
                        mode = creating ? .signIn : .create
                    }
                    .fontWeight(.semibold)
                }
                .font(.system(size: 15))
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .overlay(alignment: .topLeading) {
            backButton { onBack() }
        }
    }

    private var signInWithAppleButton: some View {
        SignInWithAppleButton(mode == .create ? .signUp : .signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            AccountManager.shared.handle(result)
            if AccountManager.shared.isSignedIn { onComplete() }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var legalText: some View {
        Text("By continuing you agree to ProtoType's [Terms](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) and [Privacy Policy](prototype-privacy:).")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "prototype-privacy" else { return .systemAction }
                showPrivacyPolicy = true
                return .handled
            })
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
            }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(width: 30, height: 30)
        .padding(.leading, 16)
        .padding(.top, 4)
    }
}

#Preview {
    AccountFlowView(onComplete: {}, onBack: {})
}
