# Architecture

## Project structure

Two Xcode targets inside one project:

```
ProtoType.xcodeproj
├── ProtoType          — host app (SwiftUI settings + onboarding + paywall)
└── PrototypeKeyboard  — keyboard extension (UIInputViewController + SwiftUI)
```

Source is split into three folders:

```
Shared/                compiled into BOTH targets
  LanguageConfig.swift     Language enum, AppGroup constants
  KeyboardProxyProtocol.swift  bridge between extension and SwiftUI views
  AutocorrectService.swift

PrototypeKeyboard/     extension only
  KeyboardViewController.swift  UIInputViewController subclass
  KeyboardView.swift            SwiftUI keyboard layout
  ProtoTypeActionHandler.swift  KeyboardKit action handler
  TranslationService.swift      Apple Translation + MyMemory fallback
  PredictionEngine.swift        bigram/trigram next-word engine
  Resources/                    translation_*.json + ngrams_*.json

ProtoType/             host app only
  ProtoTypeApp.swift, ContentView.swift, HomeView.swift …
```

There is also a `project.yml` at repo root (XcodeGen). It is **out of sync** with the actual `.xcodeproj` — do not regenerate from it. The `.xcodeproj` is the source of truth for builds.

---

## App Group

```
group.harrykhizer.ProtoType
```

Declared in both `ProtoType.entitlements` and `PrototypeKeyboard.entitlements`. Used for `UserDefaults` to share the selected language pair between the host app and the keyboard extension. Access via `AppGroup.defaults` (defined in `LanguageConfig.swift`).

---

## KeyboardKit

- **Package:** `https://github.com/KeyboardKit/KeyboardKit.git` — **source** SPM package, version 10.5.1.
- **Type:** dynamic framework (compiled from source at build time).
- **Linking:** extension target links against KK (`packageProductDependencies` entry `BEEF020100000000000A0001`).
- **Embedding:** KK is embedded in the **host app** (`ProtoType.app/Frameworks/KeyboardKit.framework`) via the main app's Frameworks build phase (`BEEF030100000000000A0001`). The extension is **not** given its own copy.
- **Why:** iOS extensions have an rpath of `@executable_path/../../Frameworks`, which resolves to the containing app's Frameworks folder at runtime. This is the standard shared-framework pattern Apple documents. Attempting to embed KK directly in the `.appex` bundle via a `productRef`-based copy phase silently fails — Xcode cannot resolve SPM `productRef` entries in `PBXCopyFilesBuildPhase`, so the framework is never copied and dyld fails to load the extension with no crash log.

**Do not** add a `PBXCopyFilesBuildPhase` entry with `productRef` to the extension target. This was the bug that caused builds 48–51 to silently fail.

### Key pbxproj identifiers (do not reuse these UUIDs)

| UUID | Role |
|---|---|
| `BEEF020000000000000A0001` | `XCRemoteSwiftPackageReference "KeyboardKit"` |
| `BEEF020100000000000A0001` | `XCSwiftPackageProductDependency` — extension links KK |
| `BEEF020200000000000A0001` | `PBXBuildFile` — KK in extension Frameworks (link only) |
| `BEEF030000000000000A0001` | `XCSwiftPackageProductDependency` — main app links KK |
| `BEEF030100000000000A0001` | `PBXBuildFile` — KK in main app Frameworks (link + embed) |

---

## KeyboardKit integration pattern

`KeyboardViewController` subclasses `KeyboardInputViewController` (KK). Initialization order matters:

1. Set up `kbState` and `predictionEngine` **before** calling `super.viewDidLoad()` because KK may call `viewWillSetupKeyboardView` from within `super.viewDidLoad()`.
2. `viewWillSetupKeyboardView` calls `setupKeyboardView { controller in ProtoTypeKeyboardView(...) }`.
3. `ProtoTypeActionHandler` subclasses `KeyboardAction.StandardActionHandler` and is assigned to `services.actionHandler` after `super.viewDidLoad()`.

`KeyboardProxy` protocol (in `Shared/`) is the boundary between the extension's `UIInputViewController` and the SwiftUI view tree. SwiftUI views hold only a `weak` reference to a `KeyboardProxy`, never a concrete `KeyboardViewController`.

---

## Translation pipeline (per keystroke)

1. Character typed → `currentPartial` updated → `PredictionEngine.predictions(for:)` prefix-searches bigram keys.
2. Space typed → `ProtoTypeActionHandler.handleSpace()`:
   a. Check `getLexicon()` (iOS text replacements) — expand and return if found.
   b. Check `AutocorrectService.correct(word:language:)` — replace in proxy if corrected.
   c. Build prediction chips: slot 0 = typed word with local translation, slots 1–2 = `freshPredictions(after:)`.
   d. If local translation missing, fire async `TranslationService.shared.translate(word:from:to:)` and update chip 0 on `MainActor`.
3. Translation hits: local JSON dictionary → `wordCache` (in-session) → Apple Translation framework → MyMemory REST API (4 s timeout).

---

## Supported languages

10 languages, 18 directional pairs shipped in the app bundle:

`ar, zh, de, en, es, fr, hi, ja, pt, ru`

All pairs are `{src}_{dst}` in `translations_{src}_{dst}.json`. Ngram files for next-word prediction are `ngrams_{lang}.json`.

---

## Info.plist notes

Both targets use `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_*` build settings — there is no static `Info.plist` for the main app. The extension has a static `Info.plist` (required for `NSExtension` dictionary).

Required keys in the main app build settings:
- `INFOPLIST_KEY_NSMicrophoneUsageDescription` — required because KK's dictation code references microphone APIs even if the app never requests access. Missing this causes App Store Connect error 90683.

---

## Signing

- Team: `7KQ7FD9TAX`
- Automatic signing (`CODE_SIGN_STYLE = Automatic`)
- Bundle IDs: `com.prototype.app.ProtoType` (host), `com.prototype.app.ProtoType.PrototypeKeyboard` (extension)
- CI builds pass `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` for simulator builds only.
