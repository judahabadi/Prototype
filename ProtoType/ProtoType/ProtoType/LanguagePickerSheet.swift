import SwiftUI

/// Bottom-sheet language picker from the design: inset card list of all
/// languages, checkmark on the current selection, the language used on the
/// other side of the pair disabled with an "in use" label.
struct LanguagePickerSheet: View {
    let title: String
    @Binding var selection: Language
    let other: Language
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(Language.allCases.enumerated()), id: \.element) { index, lang in
                        let inUse = lang == other
                        Button {
                            selection = lang
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(lang.flag)
                                    .font(.system(size: 28))
                                Text(lang.displayName)
                                    .font(.system(size: 17))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if inUse {
                                    Text("in use")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                if lang == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if index < Language.allCases.count - 1 {
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(height: 0.5)
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .disabled(inUse)
                        .opacity(inUse ? 0.35 : 1)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.fraction(0.78)])
        .presentationCornerRadius(38)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        LanguagePickerSheet(title: "I speak", selection: .constant(.english), other: .spanish)
    }
}
