import Foundation

actor TranslationService {
    static let shared = TranslationService()

    private var cache: [String: [String: String]] = [:]
    private var loadedPairKey: String? = nil

    private init() {}

    func translate(word: String,
                   from: Language,
                   to: Language) async -> String {
        let trimmed = word.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return "—" }

        let pairKey = "\(from.isoCode)_\(to.isoCode)"

        if loadedPairKey != pairKey {
            cache.removeAll()
            cache[pairKey] = loadDictionary(pairKey: pairKey)
            loadedPairKey = pairKey
        }

        if let hit = cache[pairKey]?[trimmed] {
            return hit
        }

        if let remote = await fetchRemote(word: trimmed, from: from, to: to) {
            cache[pairKey, default: [:]][trimmed] = remote
            return remote
        }

        return "—"
    }

    func evict() {
        cache.removeAll()
        loadedPairKey = nil
    }

    private func loadDictionary(pairKey: String) -> [String: String] {
        let name = "translations_\(pairKey)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        var lowered: [String: String] = [:]
        lowered.reserveCapacity(dict.count)
        for (k, v) in dict {
            lowered[k.lowercased()] = v
        }
        return lowered
    }

    private func fetchRemote(word: String,
                             from: Language,
                             to: Language) async -> String? {
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
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = obj["responseData"] as? [String: Any],
                  let translated = responseData["translatedText"] as? String,
                  !translated.isEmpty
            else {
                return nil
            }
            return translated
        } catch {
            return nil
        }
    }
}
