import SwiftUI
import StoreKit

/// Subscription paywall. Presented as a sheet from the dashboard, or — when
/// `isHardBlock` is true (trial expired, swapped in as the root view) — as a
/// full-screen block with no way to dismiss.
struct PaywallView: View {
    var isHardBlock = false

    @Environment(\.dismiss) private var dismiss
    @State private var manager = SubscriptionManager.shared
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 16) {
                Image("AppIconRounded")
                    .resizable()
                    .frame(width: 76, height: 76)
                    .shadow(color: Color(red: 40 / 255, green: 60 / 255, blue: 130 / 255).opacity(0.3),
                            radius: 13, y: 10)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text(isHardBlock ? "Your free trial has ended" : "ProtoType Premium")
                        .font(.system(size: 26, weight: .bold))

                    Text(isHardBlock
                         ? "Subscribe to keep translating as you type — in every app, in every language."
                         : "Translate as you type — in every app, in every language.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .topTrailing) {
                if !isHardBlock {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 16)
                }
            }

            // Features
            VStack(spacing: 0) {
                FeatureRow(icon: "text.bubble", color: .accentColor,
                           title: "Live word translation",
                           subtitle: "See translations above the keyboard as you type")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "brain.head.profile", color: .purple,
                           title: "Smart next-word prediction",
                           subtitle: "Trained on millions of real sentences in 10 languages")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "wifi.slash", color: .green,
                           title: "Fully offline",
                           subtitle: "Apple Translation — no internet required after setup")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "keyboard", color: .orange,
                           title: "Private by design",
                           subtitle: "Everything stays on your device")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // CTA
            VStack(spacing: 12) {
                Button {
                    Task { await subscribe() }
                } label: {
                    Group {
                        if manager.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isHardBlock ? "Subscribe — $4.99/month" : "Start Free — then $4.99/month")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .disabled(manager.isLoading)

                Button("Restore Purchase") {
                    Task { await manager.restore() }
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

                Text("Cancel anytime in Settings → Apple ID → Subscriptions.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Privacy Policy") { showPrivacyPolicy = true }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.fraction(0.93)])
        .presentationCornerRadius(38)
        .presentationDragIndicator(isHardBlock ? .hidden : .visible)
        .interactiveDismissDisabled(isHardBlock)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func subscribe() async {
        do {
            try await manager.purchase()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 12)
    }
}

#Preview("Sheet") {
    Color.clear.sheet(isPresented: .constant(true)) { PaywallView() }
}

#Preview("Hard block") {
    PaywallView(isHardBlock: true)
}
