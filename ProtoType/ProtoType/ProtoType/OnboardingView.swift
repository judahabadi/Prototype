import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0
    @State private var done = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                Group {
                    switch step {
                    case 0:
                        WelcomeScreen { advance(to: 1) }
                    case 1:
                        AccountFlowView(
                            onComplete: { advance(to: 2) },
                            onBack: { advance(to: 0) }
                        )
                    case 2:
                        LanguageScreen { advance(to: 3) }
                            .environment(appState)
                    default:
                        SetupScreen { done = true }
                            .environment(appState)
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .offset(x: 16).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if done {
                DoneOverlay {
                    appState.hasCompletedOnboarding = true
                }
                .transition(.opacity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .animation(.easeOut(duration: 0.3), value: done)
    }

    private func advance(to next: Int) {
        withAnimation(.easeOut(duration: 0.4)) { step = next }
    }

    // MARK: - Top bar: back chevron + progress dots

    private var topBar: some View {
        HStack(spacing: 0) {
            // Account step renders its own back button.
            Button {
                if step > 0 { advance(to: step - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 30, height: 30)
            .opacity(step > 0 && step != 1 ? 1 : 0)
            .disabled(step == 0 || step == 1)

            HStack(spacing: 7) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i == step ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .animation(.easeOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
    }
}

// MARK: - Shared buttons (design spec: 50pt, radius 13, 17pt semibold)

private struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(disabled ? Color(.tertiarySystemFill) : Color.accentColor)
                .foregroundStyle(disabled ? Color(.tertiaryLabel) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .disabled(disabled)
    }
}

private struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}

// MARK: - Welcome

private struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                BrandWordmark()
                Spacer().frame(height: 28)
                Text("Learn while you type.")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("ProtoType shows a live translation of every word you type — in any app.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 14) {
                FeatureRow(icon: "text.bubble", color: .accentColor, text: "See translations as you type")
                FeatureRow(icon: "brain.head.profile", color: .purple, text: "Next-word prediction in 10 languages")
                FeatureRow(icon: "wifi.slash", color: .green, text: "Works offline with Apple Translation")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 36)

            PrimaryButton(title: "Get Started", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
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
                .font(.system(size: 23))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(.system(size: 15))
            Spacer()
        }
    }
}

// MARK: - Language Selection

private struct LanguageScreen: View {
    @Environment(AppState.self) private var appState
    let onContinue: () -> Void
    @State private var pickerSide: PickerSide?

    private enum PickerSide: Identifiable {
        case native, target
        var id: Self { self }
    }

    var body: some View {
        @Bindable var state = appState
        let samePair = appState.nativeLanguage == appState.targetLanguage

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your languages")
                    .font(.system(size: 32, weight: .bold))
                Text("The keyboard translates from your native language to the one you're learning.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 16) {
                PickerRow(title: "I speak", language: appState.nativeLanguage) { pickerSide = .native }
                PickerRow(title: "I'm learning", language: appState.targetLanguage) { pickerSide = .target }
                if samePair {
                    Text("Pick two different languages to continue.")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                } else {
                    LanguagePackStatusView(from: appState.nativeLanguage, to: appState.targetLanguage)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            PrimaryButton(title: "Continue", disabled: samePair, action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
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

private struct PickerRow: View {
    let title: String
    let language: Language
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button(action: action) {
                HStack(spacing: 10) {
                    Text(language.flag)
                        .font(.system(size: 22))
                    Text(language.displayName)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Keyboard Setup

private struct SetupScreen: View {
    @Environment(AppState.self) private var appState
    let onContinue: () -> Void
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enable the keyboard")
                    .font(.system(size: 32, weight: .bold))
                Text("Follow these steps in iPhone Settings to activate ProtoType.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                SetupStep(number: 1, text: "Open **Settings**")
                SetupStep(number: 2, text: "Tap **General → Keyboard → Keyboards**")
                SetupStep(number: 3, text: "Tap **Add New Keyboard**")
                SetupStep(number: 4, text: "Select **ProtoType**")
                SetupStep(number: 5, text: "Tap ProtoType → enable **Allow Full Access**", last: true)
            }
            .padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Why Full Access?")
                        .font(.system(size: 15, weight: .semibold))
                    Text("It only lets the keyboard sync your language settings with the app. Translations run on-device with Apple Translation — nothing you type is ever sent to ProtoType's servers.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 12) {
                SecondaryButton(title: "Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }

                PrimaryButton(title: "Continue", disabled: !appState.keyboardHasLoaded, action: onContinue)

                if !appState.keyboardHasLoaded {
                    Text("Continue unlocks once ProtoType is active — tap the keyboard once after enabling it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .onAppear {
            appState.refreshKeyboardStatus()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                appState.refreshKeyboardStatus()
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())

            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !last {
                Rectangle().fill(Color(.separator)).frame(height: 0.5)
            }
        }
    }
}

// MARK: - Done overlay

private struct DoneOverlay: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.system(size: 24, weight: .bold))
            Text("Switch to ProtoType with the 🌐 key and start typing.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Open ProtoType", action: onOpen)
                .frame(maxWidth: 280)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
