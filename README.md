# Prototype — translation keyboard

iOS 17+ custom keyboard that shows a live parallel translation as you type.
Two-target Xcode project: a SwiftUI host app for language settings, and a
keyboard extension that does the work.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen][xg] —
this keeps the build configuration reviewable in git instead of inside
a binary `.pbxproj`.

    brew install xcodegen
    cd "ProtoType Keyboard"
    xcodegen generate
    open Prototype.xcodeproj

Both targets share the App Group `group.harrykhizer.ProtoType`
(declared in `*.entitlements`). The keyboard extension reads the
selected language pair from this group's `UserDefaults` at viewDidLoad.

[xg]: https://github.com/yonaskolb/XcodeGen

## Layout

    Shared/                  source files compiled into both targets
      LanguageConfig.swift
      KeyboardProxyProtocol.swift
    Prototype/               main app target
    PrototypeKeyboard/       keyboard extension target
      Resources/             24 translation_*.json dictionaries
    scripts/
      build_seed_dictionaries.py    regenerates the 24 JSON files
    project.yml              XcodeGen project definition

## Translation dictionaries — important

The 24 JSON files in `PrototypeKeyboard/Resources/` are **seed
dictionaries** containing ~180 hand-verified entries each (most-common
nouns, verbs, adjectives, function words, numbers, days, greetings).
They exist so the keyboard works offline on first launch.

The runtime always falls back to MyMemory's free translation API for
words not in the local dictionary, caches the result for the session,
and evicts on language swap. So the keyboard is fully functional with
the seed.

For App Store submission you should expand each file to 3k–10k entries
from a real source. Recommended sources, all permissively licensed:

- **Wiktionary** translation tables (CC BY-SA) — extract via
  [`wiktextract`](https://github.com/tatuylonen/wiktextract).
- **OPUS** parallel corpora ([opus.nlpl.eu](https://opus.nlpl.eu/)) —
  use word-frequency cuts to take the top N entries.
- **Tatoeba** sentence pairs (CC BY) — extract aligned word frequencies.

Drop the expanded files in `PrototypeKeyboard/Resources/` with the same
schema (flat `{ "lowercase_word": "translation" }`) and re-run
`xcodegen generate`. The schema, file naming convention, and lookup
path do not need to change.

## Architecture notes

- SwiftUI everywhere except `UIInputViewController` (Apple-mandated).
- `@Observable` (Swift 5.9+) — no `ObservableObject`.
- One language pair in RAM at a time. `TranslationService.evict()` and
  `PredictionEngine.evict()` are called on every swap.
- `PredictionEngine` keeps only sorted keys (~10kB at 10k words),
  binary-searches for prefix matches in O(log n).
- The keyboard view holds the proxy as `weak` and only via the
  `KeyboardProxy` protocol — never the concrete `UIInputViewController`.

## Privacy & App Store

- `PrivacyInfo.xcprivacy` in both targets declares no tracking, no
  collected data, and a `CA92.1` reason for `UserDefaults` access.
- `RequestsOpenAccess: true` in the extension's Info.plist (required
  for the network fallback to MyMemory).
- `NSLocalNetworkUsageDescription` in the host app explains the
  network use to the user.
- Globe key renders only when `needsInputModeSwitchKey` is true.
- Dismiss key always present.
- All tap targets ≥ 44×44 pt.
