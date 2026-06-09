import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var pollTimer: Timer?

    var body: some View {
        TabView {
            HomeTab()
                .environment(appState)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            TryItView()
                .tabItem {
                    Label("Try It", systemImage: "keyboard.fill")
                }
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

// MARK: - Home tab

private struct HomeTab: View {
    @Environment(AppState.self) private var appState
    @State private var manager = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        @Bindable var state = appState

        NavigationStack {
            List {
                // Trial banner
                if !manager.isSubscribed && !manager.trialExpired {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(manager.trialDaysRemaining) day\(manager.trialDaysRemaining == 1 ? "" : "s") left in trial")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Subscribe to keep using ProtoType")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Subscribe") { showPaywall = true }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Keyboard status banner
                if !appState.keyboardHasLoaded {
                    Section {
                        SetupCard()
                            .environment(appState)
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Keyboard is active")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Language pair
                Section("Language pair") {
                    LanguagePairCard()
                        .environment(appState)
                }

                // Change languages
                Section("Change languages") {
                    LanguageRow(title: "I speak", selection: $state.nativeLanguage)
                        .padding(.vertical, 4)
                    LanguageRow(title: "I'm learning", selection: $state.targetLanguage)
                        .padding(.vertical, 4)
                    LanguagePackStatusView(from: appState.nativeLanguage, to: appState.targetLanguage)
                        .padding(.vertical, 4)
                }

                // How to use
                Section("How to use") {
                    HowToUseCard()
                }
            }
            .navigationTitle("ProtoType")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Language pair card

private struct LanguagePairCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
        .padding(.vertical, 8)
    }
}

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
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard not enabled")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Tap to see setup steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expanded.toggle() } }

            if expanded {
                Divider().padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    SetupStepRow(number: 1, text: "Open **Settings**")
                    SetupStepRow(number: 2, text: "Go to **General → Keyboard → Keyboards**")
                    SetupStepRow(number: 3, text: "Tap **Add New Keyboard → ProtoType**")
                    SetupStepRow(number: 4, text: "Tap ProtoType → enable **Allow Full Access**")
                }
                .padding(.top, 12)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 16)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.orange, in: Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

// MARK: - How to use card

private struct HowToUseCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TipRow(icon: "text.bubble", color: .blue,
                   title: "See the translation",
                   description: "Type a word — its translation appears in the bar above the keyboard.")
            Divider()
            TipRow(icon: "hand.tap", color: .purple,
                   title: "Tap to insert",
                   description: "Tap a word chip to accept it. Long-press to insert the translation instead.")
            Divider()
            TipRow(icon: "arrow.left.arrow.right", color: .green,
                   title: "Switch languages",
                   description: "Tap the flag icon on the keyboard to change your language pair anytime.")
        }
        .padding(.vertical, 4)
    }
}

private struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
