import SwiftUI

struct TryItView: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Info strip
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.accentColor)
                Text("Switch to ProtoType with the 🌐 key, then type below")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(.separator)).frame(height: 0.5)
            }

            // Full-bleed typing area
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Enter text")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 17))
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .onTapGesture { isFocused = true }
    }
}
