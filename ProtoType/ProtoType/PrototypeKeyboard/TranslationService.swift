import Foundation
import Translation

@MainActor
final class TranslationService {
    static let shared = TranslationService()

    private var appleSession: TranslationSession?
    private var wordCache: [String: String] = [:]
    private var localDict: [String: String] = [:]
    private var loadedPairKey: String? = nil

    private init() {}

    func setSession(_ session: TranslationSession) {
        appleSession = session
        wordCache.removeAll()
    }

    func translate(word: String, from: Language, to: Language) async -> String {
        let trimmed = word.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return "—" }

        let pairKey = "\(from.isoCode)_\(to.isoCode)"
        if loadedPairKey != pairKey {
            wordCache.removeAll()
            localDict = loadDictionary(pairKey: pairKey)
            loadedPairKey = pairKey
        }

        if let hit = localDict[trimmed] { return hit }
        if let hit = wordCache[trimmed] { return hit }

        if let session = appleSession,
           let response = try? await session.translate(trimmed) {
            let result = response.targetText
            wordCache[trimmed] = result
            return result
        }

        // Fallback for language pairs unsupported by Apple Translation (e.g. Bengali, Hebrew)
        if let remote = await fetchMyMemory(word: trimmed, from: from, to: to) {
            wordCache[trimmed] = remote
            return remote
        }

        return "—"
    }

    func evict() {
        wordCache.removeAll()
        appleSession = nil
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

    private func fetchMyMemory(word: String, from: Language, to: Language) async -> String? {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: word),
            URLQueryItem(name: "langpair", value: "\(from.isoCode)|\(to.isoCode)")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rd = obj["responseData"] as? [String: Any],
                  let text = rd["translatedText"] as? String,
                  !text.isEmpty
            else { return nil }
            return text
        } catch { return nil }
    }
}
