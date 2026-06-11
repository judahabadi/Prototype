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
                    Label("Try It", systemImage: "keyboard")
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
    @State private var pickerSide: PickerSide?

    private enum PickerSide: Identifiable {
        case native, target
        var id: Self { self }
    }

    var body: some View {
        @Bindable var state = appState

        List {
            // Brand header
            Section {
                BrandWordmark(markSize: 30, fontSize: 34)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 0, trailing: 4))
            }

            // Keyboard not enabled — collapsible setup card
            if !appState.keyboardHasLoaded {
                Section {
                    SetupCard()
                }
            }

            // Trial banner
            if !manager.isSubscribed && !manager.trialExpired {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(manager.trialDaysRemaining) day\(manager.trialDaysRemaining == 1 ? "" : "s") left in trial")
                                .font(.system(size: 15, weight: .medium))
                            Text("Subscribe to keep using ProtoType")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Subscribe") { showPaywall = true }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            // Language pair — hero card
            Section {
                LanguagePairCard(
                    onPickNative: { pickerSide = .native },
                    onPickTarget: { pickerSide = .target }
                )
                LanguagePackStatusView(from: appState.nativeLanguage, to: appState.targetLanguage)
                    .padding(.vertical, 2)
            } header: {
                Text("Language pair")
            } footer: {
                Text("Tap a flag to choose from 10 languages, or tap ⇄ to swap.")
            }

            // Keyboard settings
            Section("Keyboard") {
                ToggleRow(
                    icon: "iphone.radiowaves.left.and.right",
                    tint: Color.accentColor,
                    title: "Haptic feedback",
                    subtitle: "Vibrate gently on each key press",
                    isOn: $state.hapticFeedback
                )
                ToggleRow(
                    icon: "speaker.wave.2",
                    tint: Color(.systemGray),
                    title: "Keyboard clicks",
                    subtitle: "Play a sound on each key press",
                    isOn: $state.keyboardClicks
                )
            }

            // Subscription
            Section {
                if manager.isSubscribed {
                    HStack(spacing: 12) {
                        IconTile(icon: "crown.fill", tint: Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ProtoType Premium")
                                .font(.system(size: 16, weight: .medium))
                            Text("Active")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                        }
                    }
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("Manage Subscription")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(icon: "crown.fill", tint: Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Premium")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Text("$4.99/month after 3-day free trial")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Subscription")
            } footer: {
                if !manager.isSubscribed {
                    Text("Cancel anytime in Settings → Apple ID → Subscriptions.")
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $pickerSide) { side in
            switch side {
            case .native:
                LanguagePickerSheet(title: "I speak", selection: $state.nativeLanguage,
                                    other: appState.targetLanguage)
            case .target:
                LanguagePickerSheet(title: "I'm learning", selection: $state.targetLanguage,
                                    other: appState.nativeLanguage)
            }
        }
    }
}

// MARK: - Language pair hero card

private struct LanguagePairCard: View {
    @Environment(AppState.self) private var appState
    let onPickNative: () -> Void
    let onPickTarget: () -> Void
    @State private var swapAngle = 0.0
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 0) {
            LanguageCell(language: appState.nativeLanguage, role: "Speaking", action: onPickNative)
                .opacity(dimmed ? 0.25 : 1)

            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(swapAngle))
            }
            .buttonStyle(.plain)

            LanguageCell(language: appState.targetLanguage, role: "Learning", action: onPickTarget)
                .opacity(dimmed ? 0.25 : 1)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func swap() {
        withAnimation(.spring(duration: 0.35, bounce: 0.35)) { swapAngle += 180 }
        withAnimation(.easeOut(duration: 0.15)) { dimmed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.175) {
            appState.swapLanguages()
            withAnimation(.easeIn(duration: 0.15)) { dimmed = false }
        }
    }
}

private struct LanguageCell: View {
    let language: Language
    let role: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(language.flag)
                    .font(.system(size: 46))
                Text(language.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 9)
                Text(role)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon tile + toggle row

private struct IconTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(tint, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct ToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// MARK: - Setup card (keyboard not enabled)

private struct SetupCard: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard not enabled")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Tap to see setup steps")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }

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
                    Label("Open Settings", systemImage: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.orange, in: Circle())

            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}
