import Foundation

/// Offline translation — local bundled JSON dictionaries only, no network.
///
/// Per the v1 decision (offline JSON only), the Apple Translation session and the
/// MyMemory web fallback have been removed. `translate` returns a dictionary hit
/// or "—". The `allowRemote` parameter is kept (always ignored) so existing call
/// sites compile unchanged. The shared engine logic also lives in
/// `Shared/Engines/TranslationEngine.swift`.
@MainActor
final class TranslationService {
    static let shared = TranslationService()

    private var localDict: [String: String] = [:]
    private var loadedPairKey: String? = nil

    private init() {}

    func translate(word: String, from: Language, to: Language, allowRemote: Bool = false) async -> String {
        let trimmed = word.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return "—" }

        let pairKey = "\(from.isoCode)_\(to.isoCode)"
        if loadedPairKey != pairKey {
            localDict = loadDictionary(pairKey: pairKey)
            loadedPairKey = pairKey
        }
        return localDict[trimmed] ?? "—"
    }

    func evict() {
        localDict.removeAll()
        loadedPairKey = nil
    }

    private func loadDictionary(pairKey: String) -> [String: String] {
        let name = "translations_\(pairKey)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var result: [String: String] = [:]
        result.reserveCapacity(dict.count)
        for (k, v) in dict { result[k.lowercased()] = v }
        return result
    }
}
