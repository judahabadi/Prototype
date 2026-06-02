import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = SubscriptionManager.shared
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Text("🌍")
                    .font(.system(size: 64))
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("ProtoType Premium")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Translate as you type — in every app, in every language.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .padding(.bottom, 32)

            // Features
            VStack(spacing: 0) {
                FeatureRow(icon: "globe", color: .blue,
                           title: "Live word translation",
                           subtitle: "See translations above the keyboard as you type")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "brain", color: .purple,
                           title: "Smart next-word prediction",
                           subtitle: "Trained on millions of real sentences in 10 languages")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "wifi.slash", color: .green,
                           title: "Fully offline",
                           subtitle: "Apple Translation — no internet required after setup")
                Divider().padding(.leading, 56)
                FeatureRow(icon: "lock.shield", color: .orange,
                           title: "Private by design",
                           subtitle: "Everything stays on your device")
            }
            .padding(.horizontal, 20)

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
                            Text("Start Free — then $4.99/month")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isLoading)

                Button("Restore Purchase") {
                    Task { await manager.restore() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("Cancel anytime in Settings → Apple ID → Subscriptions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Privacy Policy") { showPrivacyPolicy = true }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
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
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 14)
    }
}
