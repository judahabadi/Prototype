import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0

    var body: some View {
        switch step {
        case 0:
            WelcomeScreen { step = 1 }
        default:
            LanguageScreen {
                appState.hasCompletedOnboarding = true
            }
            .environment(appState)
        }
    }
}

// MARK: - Welcome

private struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .padding(.bottom, 40)

            VStack(spacing: 12) {
                Text("Type in any language.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("ProtoType shows a live translation\nas you type — in every app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Get Started", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
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
