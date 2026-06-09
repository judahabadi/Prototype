# Decision Log

## 2026-06-01

### Project structure
- Two build configs coexist: root `project.yml` (XcodeGen) and `ProtoType/ProtoType/ProtoType.xcodeproj` (actual Xcode project used for builds).
- The real `.xcodeproj` has team `7KQ7FD9TAX`, automatic signing, and bundle IDs under `com.prototype.app.*`.
- The `project.yml` at root describes a different bundle ID scheme (`com.prototype.keyboard.*`) — these are out of sync.

### Xcode Cloud progress
- Step 2 done: bundle IDs and App Group `group.harrykhizer.ProtoType` registered in Developer Portal.
- Step 3 done: app exists in App Store Connect under bundle ID `com.prototype.app.ProtoType`.

### Xcode Cloud blockers identified
- `IPHONEOS_DEPLOYMENT_TARGET = 26.4` in `.xcodeproj` — confirmed correct. Apple skipped 17→26; iOS 26 is the current shipping OS. Do not change this.
- Bundle IDs and App Group `group.harrykhizer.ProtoType` need to be registered in the Apple Developer Portal.
- App record needs to exist in App Store Connect.
- No Xcode Cloud workflow configured yet.
- No `ci_scripts` folder present.

### CLAUDE.md
- Created `CLAUDE.md` at repo root with four working rules: ask don't assume, simplest solution first, don't touch unrelated code, flag uncertainty explicitly.
- Committed and pushed on branch `claude/upbeat-newton-yUXN8`.
- Draft PR opened: https://github.com/judahabadi/Prototype/pull/2

### memory.md
- Decided to maintain this file to log every significant decision made during development.

---

## 2026-06-02

### KeyboardKit embedding — root cause and fix (builds 51–53)

**Problem:** Custom keyboard extension never appeared; no crash log visible.

**Root cause:** KeyboardKit is a dynamic SPM source package (not a binary xcframework). The extension target had a `PBXCopyFilesBuildPhase` entry using a `productRef` to embed KK directly into `.appex/Frameworks/`. Xcode cannot resolve `productRef` entries in copy phases for SPM products — the framework was never copied, so dyld failed silently at extension load time.

**Fix (commit `c407f93`):** Added KeyboardKit to the **main app** target's Frameworks build phase instead. Xcode embeds it in `ProtoType.app/Frameworks/`. The extension finds it at runtime via its rpath `@executable_path/../../Frameworks`, which resolves to the containing app's Frameworks folder. This is the standard iOS pattern for sharing a dynamic framework between an app and its extension. The broken embed phase was removed from the extension target entirely.

**Key pbxproj identifiers:**
- `BEEF030000000000000A0001` — `XCSwiftPackageProductDependency` for main app target
- `BEEF030100000000000A0001` — `PBXBuildFile` for KK in main app Frameworks phase
- `BEEF020300000000000A0001` / `BEEF020400000000000A0001` — REMOVED (broken extension embed entries)

### NSMicrophoneUsageDescription missing (build 52 App Store rejection, error 90683)

**Problem:** App Store Connect rejected build 52 with error 90683 — `NSMicrophoneUsageDescription` missing from main app Info.plist.

**Root cause:** Adding KeyboardKit to the main app target pulled in KK's dictation code, which references microphone APIs. Apple requires the purpose string even if the app itself never requests microphone access.

**Fix (commit `637a13a` / `8d6baf4`):** Added `INFOPLIST_KEY_NSMicrophoneUsageDescription = "Required for keyboard dictation.";` to both Debug and Release build settings for the ProtoType target in `project.pbxproj`. This injects the key into the auto-generated Info.plist at build time.

### CI destination specifier

- Changed `platform=iOS Simulator,name=iPhone 16,OS=latest` → `generic/platform=iOS Simulator` in `.github/workflows/ci.yml` because GitHub's macOS-15 runner has no named iPhone simulator installed (exit code 70).

### Phase A/B/C native feel improvements (branch `claude/upbeat-newton-yUXN8`)

Implemented per the plan in `/root/.claude/plans/optimized-zooming-wilkinson.md`:
- **A1/A2:** Replaced `UIImpactFeedbackGenerator` haptics with `UIDevice.current.playInputClick()` + `UIInputViewAudioFeedback` conformance. Respects system "Keyboard Clicks" toggle; haptics removed entirely.
- **A3:** Prediction bar height raised from 36 → 44 pt to match native QuickType bar.
- **A4:** Key height 42 → 46 pt, row spacing 11 → 12, bottom padding 6 → 8. Shift/delete/return widths made proportional via `GeometryReader`.
- **A5:** Text replacements via `requestSupplementaryLexicon`; checked before autocorrect in space handler.
- **A6:** Character preview popup on letter key press.
- **B1–B4, C1–C10:** Field-aware layout (keyboardType, autocap, secure entry, textContentType), selected-text translate chip, return-key auto-dim, dark appearance override, expanded context, paste chip, globe long-press, space-bar cursor slide.

### Branching rule (user instruction, active)
- **Do not push to main or merge PRs without explicit "merge" command from user.**
- CLAUDE.md says push to both feature branch and main — honor both but only on explicit instruction.

### QuickType bar fixes (branch `claude/festive-meitner-73xZi`)

- **Bar height 44 → 38 pt** (`KeyboardView.swift`) to match Apple's native QuickType bar height (was reading taller than native).
- **Capitalization accuracy** (`ProtoTypeActionHandler.swift`): suggestion chips now case the source word to where it lands (`casedForCursor`: capitalized at a sentence start, lowercase mid-sentence). Translations are capitalized at a sentence start but otherwise keep the dictionary's own casing (`matchTranslationCase`), so legitimately capitalized nouns (e.g. German) keep their capital mid-sentence. Fixes stray capitals on the 2nd word and lowercase-at-sentence-start.
- **Standalone English "I"**: `handleSpace` now capitalizes lone "i" / "i'm" / "i'll" etc.
- **Always 3 chips**: `PredictionEngine.nextWords` tops up from the high-frequency fallback (never returns blanks) and `padToThree` fills any remaining live-typing slots. `visibleChipCount` is now always 3 (no longer drops the 3rd chip for long content — long content scrolls instead).
- **Next-word chips get translations**: `handleSpace`/punctuation paths call `translateMissingChips` so next-word suggestions show translations on-device instead of bare native words.
- **Long words/highlighted text scroll**: prediction chips and the selection translate/fix chips are wrapped in a horizontal `ScrollView` (`defaultScrollAnchor(.center)`/`.leading`) so long content scrolls rather than being clipped/shrunk. (Verify tap + long-press reliability on device.)
- **Word learning**: `AutocorrectService.note(typedWord:)` counts committed words in `AppGroup.defaults` (`typedWordFrequency`) and calls `UITextChecker.learnWord` after 3 uses, so frequently typed words stop being autocorrected and start appearing as suggestions — mirroring Apple's behaviour.

### Typing-feel fixes (diagnosis follow-up, branch `claude/festive-meitner-73xZi`)

- **Single capitalization authority**: removed the per-keystroke delete/re-insert case correction in `ProtoTypeActionHandler` (it raced fast typing → dropped/doubled letters) and the double async `resyncKeyboardCase` pass. `resyncKeyboardCase` now drives KeyboardKit's `keyboardCase` once per change, sharing one rule (`Autocap.shouldUppercase`, in `KeyboardViewController.swift`) with the action handler's `shouldCapitalize`/`casedForCursor`, so shift state and chip casing can't disagree. (KeyboardKit's own autocap left enabled; shared logic means they agree. Needs on-device verification.)
- **Consistent suggestion paths**: every "word finished" branch (space, punctuation, double-space→". ", duplicate-space, text expansion, empty word) now routes through `refreshNextWordPredictions()` (cased + padded to 3 + translated) instead of bare lowercase/untranslated `nextWords`.
- **Less chip jitter**: `carryOverTranslations` reuses a translation already shown for the same word when chips rebuild each keystroke, so known translations don't flicker off/on.
- Not done (user didn't select): filtering low-quality 1-letter ngram tokens (`s`,`i`,`t`) and the next-word-guesses-mixed-into-the-word-being-typed behaviour.

### Capitalization regressions follow-up (branch `claude/festive-meitner-73xZi`)

User report: some mid-sentence words (the/to/car) still capitalized; bar translations still capital mid-sentence.
- **Restored the async `resyncKeyboardCase` re-apply** in `textDidChange` (removing it let KeyboardKit's late auto-cap pass win, capitalizing some mid-sentence words). It re-applies our case on the next runloop so we're the last writer.
- **Autocorrections are now case-matched to the sentence** in `handleSpace` (`firstLetterCased(correction, uppercase: wantUpper)` where `wantUpper` is judged from the text *before* the word) — `UITextChecker` often returns a Capitalized guess (e.g. typo→"Car") that previously capitalized a mid-sentence word.
- **Machine translations are case-matched to the source** (`machineCased`): the local dictionaries are all lowercase, so any translation fetched at runtime (Apple/MyMemory) is machine output and is sentence-cased; it now follows the source word's case (lowercase mid-sentence). Dictionary-sourced translations still use `matchTranslationCase` (preserve).

### QuickType bar height + vertical centering (branch `claude/festive-meitner-73xZi`)

User: bar still taller than Apple's and words sit low / not centred. (Apple doesn't publish the exact bar height; KeyboardKit's iOS-26 standardPhone row is 51pt and its autocomplete toolbar is taller still, so neither is a match — tuning by eye against the native bar.)
- **Vertical centering fix**: prediction chips and selection chips were stretching content with `.frame(maxHeight: .infinity)` inside a horizontal `ScrollView`, which left them sitting low. Now the ScrollView hugs content height via `.fixedSize(horizontal: false, vertical: true)` and is centred in the bar with `.frame(maxHeight: .infinity, alignment: .center)`.
- **Height 38 → 36 pt**, chip vertical padding 5 → 4. Easily tuned in `KeyboardView.swift` (`predictionBar.frame(height:)`).

### Capitalization root fix + bar height/re-entry (branch `claude/festive-meitner-73xZi`)

User: still seeing The/To/Car capitalized mid-sentence; bar height reverts to the uncentred/too-tall "bug design" after switching keyboards and back; wants 37pt.
- **Disabled KeyboardKit's own auto-capitalization** (`state.keyboardContext.settings.isAutocapitalizationEnabled = false`) in `viewDidLoad` and re-asserted in `viewWillAppear`. The resync-only-as-last-writer approach kept losing to KeyboardKit's (sometimes async) auto-cap; disabling it makes `resyncKeyboardCase` the sole authority. Intentional capitals still work via shift (shift overrides keyboardCase for one letter).
- **`viewWillAppear` now re-asserts the setting + `resyncKeyboardCase()`** so behaviour/case is consistent after a keyboard switch.
- **Bar height → 37pt via `ProtoTypeKeyboardView.barHeight` constant**, used for the bar frame AND each chip's explicit row height. Replaced the fragile `.fixedSize`/`maxHeight:.infinity` centering (which reverted to uncentred/too-tall after keyboard switches) with an explicit per-chip `.frame(height: barHeight)` so chips are reliably centred across re-entry. Applied to prediction chips and selection chips.
- NOTE: `settings.isAutocapitalizationEnabled` is my best read of the KeyboardKit 10.5 API (search showed `onAutocapitalizationEnabledChanged` on `KeyboardSettings`); CI validates the build. If it fails to compile, the path is wrong — adjust.

### Revert to KeyboardKit's native capitalization (branch `claude/festive-meitner-73xZi`)

User decision: "keep the keyboardkit logic not ours." Our custom case layer kept fighting KeyboardKit and was likely the cause of the mid-sentence over-capitalization. Removed: `resyncKeyboardCase()` and all its calls, the `isAutocapitalizationEnabled = false` lines (re-enables KeyboardKit auto-cap), and the per-letter delete/reinsert correction (already gone on main; PR #20 which re-added it was abandoned). KeyboardKit now fully owns the typed-letter case. Kept: suggestion-bar chip casing (`casedForCursor`/`matchedCase`/`Autocap.shouldUppercase`) and `handleSpace` autocorrect case-matching — these only affect the suggestion bar display, not what KeyboardKit inserts.

### Apple-style contractions (branch `claude/festive-meitner-73xZi`)

User: "ill" doesn't auto-fix to "I'll" like Apple. Confirmed KeyboardKit (free; Pro not installed) isn't doing autocomplete here — the app uses its own engine. Added `englishContractions` map in `ProtoTypeActionHandler` and a branch in `handleSpace` (English only, takes priority over UITextChecker). ill→I'll, im→I'm, ive→I've, id→I'd (always capital-I), plus dont/doesnt/cant/wont/youre/theyre/weve/thats/hes/shes etc. (cased to sentence position). Apostrophe is curly (’) unless smartQuotes off. Deliberately omitted ambiguous-with-real-word forms (its, were, well, wed, lets, hell, shell). Tradeoff: "ill"/"id" will also fire when the user means the real words (sick / id) — Apple does this too.

### Centering bug found (branch `claude/festive-meitner-73xZi`)

Root cause: prediction chips were wrapped in a horizontal `ScrollView` with `defaultScrollAnchor(.center)` — but that only sets scroll offset when content OVERFLOWS. When a word is shorter than its slot (normal case), a ScrollView pins it to the LEADING edge, so words sat left-of-centre. Removed the per-chip ScrollView; chip content is now centred in each slot via `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.center)`. Trade-off: long words truncate (lineLimit 1) instead of scrolling — centering was the explicit ask. (Selection chips still use ScrollView; their text is usually long.)

### Capitalization root cause FOUND (branch `claude/festive-meitner-73xZi`)

Symptom (user): every word after a space capitalized ("The To Car"), in EVERY app, when TYPING LETTERS (not tapping chips). Persisted even after PR #20 reverted to KeyboardKit-native autocap.

Root cause: the action handler replaces the `.space` action with our own `handleSpace()` and never calls `standard?(controller)`, so KeyboardKit's "lowercase the next word after a mid-sentence space" never runs. `handleSpace` inserts the trailing space but never set `keyboardCase`. The `.character` path DOES call `standard`, which is why the first word + within-word letters were correct — only post-space words were wrong. The shared `Autocap.shouldUppercase` rule itself was already correct.

Fix: disabled KeyboardKit's native autocap (`state.keyboardContext.settings.isAutocapitalizationEnabled = false` in viewDidLoad) and made `applyAutoCase()` the sole authority — it sets `keyboardContext.keyboardCase = .capitalized/.lowercased` from `Autocap.shouldUppercase(documentContextBeforeInput)` on every `textDidChange`/`selectionDidChange` + on appear. Guards `isCapsLocked` so manual caps-lock is preserved; manual single-shift still gives one capital (textDidChange resets case after the letter is inserted). NEEDS on-device verification + CI must confirm the `isCapsLocked`/`keyboardCase` API names compile.

### THE REAL "no effect" cause: ci_scripts was lost in a rebase AND in the wrong place (branch `claude/festive-meitner-73xZi`)

Symptom: user deleted + reinstalled the app and BOTH bugs (centering + every-word capitalization) were unchanged. Investigation: the keyboard source on `main` and the feature branch is byte-identical and CI is green — so the source fixes ARE deployed and DO compile. Two unrelated fixes both having zero effect ⇒ the binary on the device is not built from this source.

Root cause: the build-number fix from commit `15ff7ba` (`ci_scripts/ci_post_clone.sh`) was **orphaned by a later rebase** — it survives only as a dangling stash (`d58bde8 WIP on…`), is on no branch, and never reached `main`. So Xcode Cloud still builds with `CURRENT_PROJECT_VERSION = 1` (all targets, `GENERATE_INFOPLIST_FILE = YES` ⇒ `CFBundleVersion` = 1). App Store Connect rejects the duplicate build number, TestFlight keeps serving the original build, and delete+reinstall just re-pulls that same stale build. That is why every code change "has no effect."

Compounding bug: even when it existed, the script was at the **repo root**. Xcode Cloud only runs a `ci_scripts/` folder that sits in the **same directory as the `.xcodeproj`/workspace**. The project is at `ProtoType/ProtoType/ProtoType.xcodeproj`, so the script must live at `ProtoType/ProtoType/ci_scripts/`.

Fix: restored `ci_post_clone.sh` at `ProtoType/ProtoType/ci_scripts/` (correct location), executable (mode 100755), stamping `CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER` into the pbxproj on every Xcode Cloud build. After this merges and an Xcode Cloud build runs, TestFlight should show a NEW build number/date; install it, then remove + re-add the keyboard (iOS caches the .appex). Only then do the centering/capitalization fixes actually reach the device.
Assumption flagged: this assumes the user installs via TestFlight/Xcode Cloud (strongly implied by commit `15ff7ba` and prior memory). If they build locally from Xcode instead, the build-number issue is irrelevant and we'd look at target membership / scheme next.

---

## 2026-06-08

### Keyboard rebuild (branch `claude/keen-franklin-1OEEj`, PR #33)

Decision: rebuild the keyboard on free KeyboardKit with a permissive engine stack,
keeping all Xcode infra (signing, bundle IDs, App Group, `ci_scripts`, entitlements)
and git history; rewrite the keyboard source. All design decisions are recorded in
`APPLE_KEYBOARD_IOS26.md` §9.

**Architecture finding:** the project uses Xcode 16 **file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`), so new files in a synced folder auto-compile —
no `project.pbxproj` editing needed. `Shared/` is a member of both the app and the
extension targets, and the test target `@testable import ProtoType`s the app, so engine
code placed in `Shared/Engines/` is usable by all three and unit-testable.

**Engines (`Shared/Engines/`, with `ProtoTypeTests/EngineTests.swift`):**
- `AutocorrectEngine` — UITextChecker detection + candidate words re-ranked by
  keyboard-key distance (fixes `wint→wont`, which frequency ranking alone does not).
- `NextWordEngine` — bigram + stupid-backoff + prefix completions; consumes the bundled
  `ngrams_en.json` (top-5/head) and `unigrams_en.txt` (OpenSubtitles word
  frequencies, top-50k). No SymSpell (it wouldn't fix `wint→wont` and adds a dependency).
- `TranslationEngine` — offline local-JSON lookup + lemma fallback.

**Keyboard behaviour changes:**
- KeyboardKit fully owns autocap; typed letters delegate to its standard handler
  (removed our `insertCasedLetter`/`applyAutoCase`/autocap-disable). This is the real
  fix for the long-standing mid-sentence-capital bug — the old build replaced `.space`/
  `.character` and starved KeyboardKit's own case logic.
- Translation is offline-only: removed the Apple Translation session + MyMemory fallback
  from `TranslationService` and the Apple Translation machinery from `KeyboardView`.
- Chips: `word (translation)` parentheses gloss (translation dimmed); tap = word,
  long-press = translation; the whole chip row scrolls as one unit when long; slot 0
  keeps the committed word after space. Removed the temp build-number marker.
- Apple-parity: A1 undo-autocorrect (backspace right after a correction reverts it, via a
  skip-flag so the paired release can't clip the restored word), A2 smart spacing
  (`word ,`→`word,`), A3 double-capital fix (`THe`→`The`, acronyms preserved).

**Deferred / verify-on-device:** A4 abbreviation-aware autocap and B4 caps-lock are left to
on-device verification (KeyboardKit likely handles them now that it owns case); A5 predictive
emoji, B1 swipe typing, B3 dictation, custom emoji plane are out of v1.

**Kept pragmatically (flagged):** chips still render in our own bar (not KeyboardKit's
toolbar slot) and smart punctuation still uses the existing custom code — both compile and
work; switching to the literal KeyboardKit versions was deferred to avoid blind rewrites of
the binary-distributed KeyboardKit 10.5.1 API. The old `PredictionEngine`/`AutocorrectService`
remain wired (functionally equal to the new Shared engines); a full swap is optional cleanup.

**Note:** `NOTICES.md` added (KeyboardKit MIT, OpenSubtitles next-word data). The temporary
`bypassPaywallForTesting` flag merged earlier (PR #32) is still on `main` — set it back to
false before shipping.
