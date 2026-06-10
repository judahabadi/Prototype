import SwiftUI

/// Create Account / Sign In screens from the onboarding design.
/// UI-only for now: no auth backend is wired up — every path simply
/// calls `onComplete` so onboarding can continue.
struct AccountFlowView: View {
    let onComplete: () -> Void
    let onBack: () -> Void

    private enum Mode { case create, signIn, email }
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch mode {
            case .create, .signIn:
                landing(creating: mode == .create)
            case .email:
                emailForm
            }
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
                     ? "Save your languages and subscription, and sync across your devices."
                     : "Sign in to restore your subscription and settings.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .frame(minHeight: 42, alignment: .top)
            }

            Spacer()

            VStack(spacing: 12) {
                signInWithAppleButton

                HStack(spacing: 12) {
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    Text("or").font(.system(size: 13)).foregroundStyle(.tertiary)
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                }
                .padding(.vertical, 4)

                Button {
                    mode = .email
                } label: {
                    Label(creating ? "Sign up with Email" : "Sign in with Email",
                          systemImage: "envelope")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

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
        // Visual stand-in: real Sign in with Apple needs the entitlement + a backend.
        Button(action: onComplete) {
            Label("Sign in with Apple", systemImage: "apple.logo")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(colorScheme == .dark ? Color.white : Color.black)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Email sign-up form

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign up with email")
                    .font(.system(size: 30, weight: .bold))
                Text("We'll keep your translation packs and preferences in sync.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 44)
            .padding(.bottom, 28)

            VStack(spacing: 0) {
                field(icon: "person", placeholder: "Full name", text: $name)
                fieldDivider
                field(icon: "envelope", placeholder: "Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                fieldDivider
                passwordField
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Use at least 6 characters.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.horizontal, 4)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onComplete) {
                    Text("Create Account")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(formValid ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(formValid ? Color.white : Color(.tertiaryLabel))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!formValid)

                legalText
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .overlay(alignment: .topLeading) {
            backButton { mode = .create }
        }
    }

    private var formValid: Bool {
        email.contains("@") && password.count >= 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 17))
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Group {
                if showPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .font(.system(size: 17))
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var fieldDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }

    private var legalText: some View {
        Text("By continuing you agree to ProtoType's **Terms** and **Privacy Policy**.")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 4)
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
