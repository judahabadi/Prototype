import SwiftUI

struct LanguagePickerView: View {
    @Bindable var state: KeyboardState
    let reloadEngines: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: Side = .native

    enum Side: String, CaseIterable, Identifiable {
        case native, target
        var id: String { rawValue }
        var label: String {
            switch self {
            case .native: return "I type in"
            case .target: return "I'm learning"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .leading),
        GridItem(.flexible(), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $editing) {
                ForEach(Side.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Language.allCases) { lang in
                        cell(for: lang)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium])
        .background(Color(uiColor: .systemBackground))
    }

    private func cell(for lang: Language) -> some View {
        let isSelected = (editing == .native && lang == state.nativeLanguage)
            || (editing == .target && lang == state.targetLanguage)
        let isOtherSide = (editing == .native && lang == state.targetLanguage)
            || (editing == .target && lang == state.nativeLanguage)

        return Button {
            guard !isOtherSide else { return }
            select(lang)
        } label: {
            HStack(spacing: 10) {
                Text(lang.flag)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.displayName)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                    Text(lang.nativeName)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color(uiColor: .secondarySystemBackground))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .opacity(isOtherSide ? 0.4 : 1)
        }
        .disabled(isOtherSide)
    }

    private func select(_ lang: Language) {
        let defaults = AppGroup.defaults
        switch editing {
        case .native:
            state.nativeLanguage = lang
            defaults.set(lang.rawValue, forKey: AppGroup.nativeKey)
        case .target:
            state.targetLanguage = lang
            defaults.set(lang.rawValue, forKey: AppGroup.targetKey)
        }
        reloadEngines()
        dismiss()
    }
}
