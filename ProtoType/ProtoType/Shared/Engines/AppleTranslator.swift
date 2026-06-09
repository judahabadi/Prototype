import Foundation
import Translation
import Observation

/// Live, on-device translation for the suggestion bar, backed by Apple's
/// Translation framework — the single translation source (the bundled JSON
/// dictionaries are no longer used).
///
/// Apple Translation is async and gated on a downloaded language pack, so the
/// bar can't get a gloss synchronously the way the offline dictionary allowed:
/// - The hosting SwiftUI view drives a `.translationTask(configuration)`; when a
///   session is handed back it calls `run(session:initial:)`, which stays alive
///   and pulls words to translate off an `AsyncStream`.
/// - `translation(for:)` returns the cached gloss or nil. The bar renders a chip
///   without a gloss until the async result lands in `cache`, then re-renders.
/// - `request(_:)` enqueues any uncached words. With no pack/session it's a quiet
///   no-op (predictions + autocorrect still work).
///
/// A single shared instance so the keyboard controller can evict the cache on a
/// memory warning while the SwiftUI view reads from it.
@MainActor
@Observable
final class AppleTranslator {

    static let shared = AppleTranslator()

    /// Drives the view's `.translationTask`; set by `configure` on a pair change.
    var configuration: TranslationSession.Configuration?

    /// Word (lowercased) → translation. Reading this in a view body is what makes
    /// the bar re-render when an async result arrives.
    private var cache: [String: String] = [:]
    private var continuation: AsyncStream<String>.Continuation?
    private var pairKey = ""

    private init() {}

    /// Point at a language pair. Idempotent — a no-op when the pair is unchanged,
    /// so the view calling this on every `onAppear` doesn't tear down the live
    /// session. On a real change it clears stale glosses and resets `configuration`
    /// so the view's `.translationTask` restarts.
    func configure(from: Language, to: Language) {
        let key = "\(from.appleTranslationLocale)->\(to.appleTranslationLocale)"
        guard key != pairKey else { return }
        pairKey = key
        continuation?.finish()
        continuation = nil
        cache.removeAll()
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: from.appleTranslationLocale),
            target: Locale.Language(identifier: to.appleTranslationLocale)
        )
    }

    /// Run the translation loop for a live session. Stays alive (via the stream)
    /// so the captured session keeps working as new words arrive; ends when the
    /// pair changes (the stream is finished) or the task is cancelled.
    func run(session: TranslationSession, initial: [String]) async {
        let (stream, cont) = AsyncStream<String>.makeStream()
        continuation?.finish()
        continuation = cont
        enqueue(initial)
        for await word in stream {
            let key = word.lowercased()
            guard cache[key] == nil else { continue }
            if let response = try? await session.translate(word) {
                cache[key] = response.targetText
            }
        }
    }

    /// Cached gloss for a word, or nil if not translated yet.
    func translation(for word: String) -> String? {
        cache[word.lowercased()]
    }

    /// Translate any of these words we don't already have a gloss for.
    func request(_ words: [String]) {
        enqueue(words)
    }

    /// Drop cached glosses on memory pressure (keeps the session alive).
    func evict() {
        cache.removeAll()
    }

    private func enqueue(_ words: [String]) {
        guard let continuation else { return }
        for word in words {
            let key = word.lowercased()
            guard !key.isEmpty, cache[key] == nil else { continue }
            continuation.yield(word)
        }
    }
}
