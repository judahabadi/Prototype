import Foundation

/// On-device "don't-correct" list (PLAN.md issue 9).
///
/// The only personalization we keep: when the user reverts the same autocorrect
/// twice (issue 7 supplies the revert signal), we stop correcting that word.
/// No typing history, no frequency learning — just a small word set, stored in
/// the App Group so the keyboard and the host app share it.
///
/// Backed by an injectable `Store` so the logic is unit-testable without
/// touching real `UserDefaults`.
final class DontCorrectList {

    /// Persistence seam. The default implementation reads/writes the App Group.
    protocol Store: AnyObject {
        func stringArray(forKey key: String) -> [String]?
        func dictionary(forKey key: String) -> [String: Int]?
        func set(_ value: Any?, forKey key: String)
    }

    private let store: Store
    private let revertThreshold: Int

    private static let wordsKey = "dontCorrect.words"
    private static let countsKey = "dontCorrect.revertCounts"

    /// `revertThreshold` reverts of the same word add it to the list.
    init(store: Store = UserDefaultsStore(), revertThreshold: Int = 2) {
        self.store = store
        self.revertThreshold = revertThreshold
    }

    // MARK: - Queries

    /// Words the user has told us not to correct.
    private(set) var words: Set<String> {
        get { Set(store.stringArray(forKey: Self.wordsKey) ?? []) }
        set { store.set(Array(newValue), forKey: Self.wordsKey) }
    }

    /// True when autocorrect should leave this word alone.
    func shouldSkip(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    // MARK: - Learning

    /// Record that the user reverted a correction for `word`. Once the same word
    /// is reverted `revertThreshold` times it joins the don't-correct list.
    /// Returns true if this call added the word.
    @discardableResult
    func recordRevert(of word: String) -> Bool {
        let key = word.lowercased()
        guard !key.isEmpty else { return false }
        if words.contains(key) { return false }

        var counts = store.dictionary(forKey: Self.countsKey) ?? [:]
        let next = (counts[key] ?? 0) + 1
        if next >= revertThreshold {
            counts[key] = nil
            store.set(counts, forKey: Self.countsKey)
            var w = words; w.insert(key); words = w
            return true
        } else {
            counts[key] = next
            store.set(counts, forKey: Self.countsKey)
            return false
        }
    }

    /// Settings "clear my list" action.
    func clear() {
        store.set([String](), forKey: Self.wordsKey)
        store.set([String: Int](), forKey: Self.countsKey)
    }

    // MARK: - Default App Group store

    final class UserDefaultsStore: Store {
        private let defaults: UserDefaults
        init(defaults: UserDefaults = AppGroup.defaults) { self.defaults = defaults }
        func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }
        func dictionary(forKey key: String) -> [String: Int]? { defaults.dictionary(forKey: key) as? [String: Int] }
        func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
    }
}
