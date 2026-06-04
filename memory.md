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
