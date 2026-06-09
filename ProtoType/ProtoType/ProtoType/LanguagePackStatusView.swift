import SwiftUI
import Translation

/// Status + auto-download for the Apple Translation pack of a language pair.
/// Drop it under the language pickers: selecting a pair triggers the check and,
/// if needed, the download (with iOS's one-time consent sheet).
struct LanguagePackStatusView: View {
    let from: Language
    let to: Language
    @State private var manager = LanguagePackManager()

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .task(id: [from, to]) {
            await manager.prepare(from: from, to: to)
        }
        .translationTask(manager.configuration) { session in
            await manager.download(using: session)
        }
    }

    @ViewBuilder private var icon: some View {
        switch manager.status {
        case .checking, .downloading:
            ProgressView().controlSize(.mini)
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unsupported:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private var message: String {
        switch manager.status {
        case .idle: return ""
        case .checking: return "Checking translation pack…"
        case .downloading: return "Downloading \(to.displayName) translation pack…"
        case .installed: return "\(to.displayName) translation ready — works on-device."
        case .unsupported: return "Apple Translation doesn’t support this pair yet."
        case .failed: return "Couldn’t prepare the translation pack."
        }
    }
}
