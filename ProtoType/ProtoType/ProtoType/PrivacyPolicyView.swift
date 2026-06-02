import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Last updated June 2, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)

                    CalloutBox {
                        Text("**Short version:** ProtoType does not collect, store, or sell your personal data. What you type stays on your device.")
                            .font(.subheadline)
                    }
                    .padding(.bottom, 24)

                    PolicySection(title: "What ProtoType does") {
                        Text("ProtoType is a keyboard extension that shows a live translation of words you type, powered by Apple's on-device Translation framework. Everything happens locally on your iPhone.")
                    }

                    PolicySection(title: "Data we do not collect") {
                        BulletList(items: [
                            "We do not collect or store what you type.",
                            "We do not create user accounts.",
                            "We do not use advertising networks or tracking pixels.",
                            "We do not sell or share data with third parties.",
                            "We have no analytics or crash-reporting SDKs in the app.",
                        ])
                    }

                    PolicySection(title: "Translation") {
                        Text("ProtoType uses **Apple Translation** (on-device) as its primary translation engine. Words you type are processed entirely on your device by Apple's framework and never leave it.")
                            .padding(.bottom, 8)
                        Text("As a fallback for any language pair not yet supported by Apple Translation, ProtoType may send the word to the **MyMemory translation API**. In that case, the individual word — but never surrounding context or identifying information — is transmitted over HTTPS. MyMemory's privacy policy is available at their website.")
                    }

                    PolicySection(title: "Subscriptions and payments") {
                        Text("ProtoType offers an optional subscription processed entirely by **Apple's App Store** (StoreKit). We never see, store, or process your payment information. Apple's privacy policy governs those transactions.")
                            .padding(.bottom, 8)
                        Text("ProtoType stores only a Boolean flag (subscribed / not subscribed) locally on your device to determine which features are available.")
                    }

                    PolicySection(title: "Keyboard extension permissions") {
                        Text("ProtoType requests **Full Access** for the keyboard extension. This is required to use the Apple Translation framework for on-device translation. Full Access does *not* mean we read or transmit what you type — we do not.")
                    }

                    PolicySection(title: "Data shared between the app and keyboard extension") {
                        Text("ProtoType uses an App Group (a standard iOS mechanism) to share your selected language pair and subscription status between the main app and the keyboard extension. This data lives entirely on your device and is never transmitted externally.")
                    }

                    PolicySection(title: "Children's privacy") {
                        Text("ProtoType does not knowingly collect any information from children under 13. The app contains no features designed to collect personal data from any user.")
                    }

                    PolicySection(title: "Changes to this policy") {
                        Text("If we make material changes, we will update the date at the top of this page. Continued use of the app after changes constitutes acceptance of the updated policy.")
                    }

                    PolicySection(title: "Contact") {
                        Text("Questions about this policy? Email us at ")
                        + Text("support@prototype-app.com")
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Helpers

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }
}

private struct CalloutBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
