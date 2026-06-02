import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0

    var body: some View {
        switch step {
        case 0:
            WelcomeScreen { step = 1 }
        case 1:
            LanguageScreen { step = 2 }
                .environment(appState)
        default:
            SetupScreen {
                appState.hasCompletedOnboarding = true
            }
        }
    }
}

// MARK: - Welcome

private struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("🌍")
                    .font(.system(size: 80))

                VStack(spacing: 12) {
                    Text("Learn while you type.")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("ProtoType shows a live translation of every word you type — in any app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                FeatureRow(icon: "text.bubble.fill", color: .blue, text: "See translations as you type")
                FeatureRow(icon: "brain.head.profile", color: .purple, text: "Next-word prediction in 10 languages")
                FeatureRow(icon: "wifi.slash", color: .green, text: "Works offline with Apple Translation")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)

            Button("Get Started", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Language Selection

private struct LanguageScreen: View {
    @Environment(AppState.self) private var appState
    let onContinue: () -> Void

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your languages")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("The keyboard translates from your native language to the one you're learning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 40)

            VStack(spacing: 16) {
                LanguageRow(title: "I speak", selection: $state.nativeLanguage)
                LanguageRow(title: "I'm learning", selection: $state.targetLanguage)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(appState.nativeLanguage == appState.targetLanguage)
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
        }
    }
}

// MARK: - Keyboard Setup

private struct SetupScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable the keyboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Follow these steps in iPhone Settings to activate ProtoType.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 32)

            VStack(spacing: 0) {
                SetupStep(number: 1, text: "Open **Settings**")
                SetupStep(number: 2, text: "Tap **General → Keyboard → Keyboards**")
                SetupStep(number: 3, text: "Tap **Add New Keyboard**")
                SetupStep(number: 4, text: "Select **ProtoType**")
                SetupStep(number: 5, text: "Tap ProtoType → enable **Allow Full Access**")
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("I'll do this later", action: onContinue)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.blue, in: Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shared picker row

struct LanguageRow: View {
    let title: String
    @Binding var selection: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(Language.allCases) { lang in
                    Button {
                        selection = lang
                    } label: {
                        if lang == selection {
                            Label("\(lang.flag) \(lang.displayName)", systemImage: "checkmark")
                        } else {
                            Text("\(lang.flag) \(lang.displayName)")
                        }
                    }
                }
            } label: {
                HStack {
                    Text("\(selection.flag) \(selection.displayName)")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
