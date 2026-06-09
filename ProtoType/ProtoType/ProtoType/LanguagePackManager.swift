import Foundation
import Translation
import Observation

/// Drives downloading of the Apple on-device translation pack for the selected
/// language pair. Selecting a pair *is* the trigger — `prepare` checks
/// availability and, when a pack is supported but not yet installed, sets a
/// `configuration` that the hosting view feeds to `.translationTask`, whose
/// action calls `download(using:)` → `prepareTranslation()`. iOS shows its
/// one-time consent sheet the first time a model downloads.
@MainActor
@Observable
final class LanguagePackManager {

    enum Status: Equatable {
        case idle          // pair not set / native == target
        case checking      // querying availability
        case downloading   // pack supported, fetching the model
        case installed     // ready on-device
        case unsupported   // Apple Translation has no model for this pair
        case failed        // download/check failed
    }

    private(set) var status: Status = .idle

    /// Drives the host view's `.translationTask`; non-nil only while a download
    /// is needed.
    var configuration: TranslationSession.Configuration?

    /// Check availability for the pair and, if needed, begin downloading.
    func prepare(from: Language, to: Language) async {
        guard from != to else {
            status = .idle
            configuration = nil
            return
        }
        let source = Locale.Language(identifier: from.appleTranslationLocale)
        let target = Locale.Language(identifier: to.appleTranslationLocale)

        status = .checking
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            status = .installed
            configuration = nil
        case .supported:
            status = .downloading
            configuration = TranslationSession.Configuration(source: source, target: target)
        case .unsupported:
            status = .unsupported
            configuration = nil
        @unknown default:
            status = .failed
            configuration = nil
        }
    }

    /// Called from `.translationTask` with the live session: download the model,
    /// then mark installed.
    func download(using session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            status = .installed
        } catch {
            status = .failed
        }
        configuration = nil
    }
}
