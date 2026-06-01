import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var pollTimer: Timer?

    var body: some View {
        @Bindable var state = appState

        NavigationStack {
            List {
                // Language pair card
                Section {
                    VStack(spacing: 20) {
                        HStack(spacing: 0) {
                            LanguageCell(language: appState.nativeLanguage, label: "Speaking")
                            Spacer()
                            Button {
                                appState.swapLanguages()
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            LanguageCell(language: appState.targetLanguage, label: "Learning")
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Keyboard setup card
                if !appState.keyboardHasLoaded {
                    Section {
                        SetupCard()
                            .environment(appState)
                    }
                }

                // Change language pair
                Section("Languages") {
                    Picker("I speak", selection: $state.nativeLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }

                    Picker("I'm learning", selection: $state.targetLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                }
            }
            .navigationTitle("ProtoType")
        }
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                appState.refreshKeyboardStatus()
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }
}

// MARK: - Language cell

private struct LanguageCell: View {
    let language: Language
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(language.flag)
                .font(.system(size: 44))
            Text(language.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Setup card

private struct SetupCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard not set up")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Tap to finish setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}
