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
