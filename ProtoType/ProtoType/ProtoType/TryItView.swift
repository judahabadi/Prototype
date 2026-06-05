import SwiftUI

struct TryItView: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private let prompts = [
        "Where is the nearest coffee shop?",
        "I would like to order something to eat.",
        "Can you help me find my hotel?",
        "What time does the museum open?",
        "I'm looking for a good restaurant nearby.",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instruction banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Switch to the ProtoType keyboard using the 🌐 key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))

                Divider()

                // Typing area
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Start typing to test the keyboard…")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Try a phrase row
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try a phrase")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(prompts, id: \.self) { prompt in
                                Button {
                                    text = prompt
                                    isFocused = true
                                } label: {
                                    Text(prompt)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Try It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !text.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            text = ""
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
