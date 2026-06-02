# Release Process

## Prerequisites

- Xcode 16.3+ (matches CI: `Xcode_16.3.app`)
- Apple Developer account with team `7KQ7FD9TAX`
- App record exists in App Store Connect under bundle ID `com.prototype.app.ProtoType`
- App Group `group.harrykhizer.ProtoType` registered in Developer Portal for both bundle IDs

---

## Steps to ship a build

1. **Pull latest main**
   ```bash
   git pull origin main
   ```

2. **Open the project**
   ```bash
   open ProtoType/ProtoType/ProtoType.xcodeproj
   ```
   Do **not** run XcodeGen — `project.yml` is out of sync with the real `.xcodeproj`.

3. **Bump the version** (if shipping a new App Store version)
   - In Xcode: select the `ProtoType` target → General → Version (marketing) and Build (integer, increment by 1).
   - Both fields live in the main target's build settings as `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

4. **Archive**
   - Product → Archive
   - Scheme: `ProtoType`, destination: `Any iOS Device (arm64)`
   - Wait for the Organizer window to open

5. **Distribute**
   - Organizer → select the new archive → Distribute App
   - Choose: App Store Connect → Upload
   - Leave all default options checked (bitcode stripped, symbols included)
   - Sign in with Apple ID for team `7KQ7FD9TAX` if prompted

6. **TestFlight**
   - App Store Connect → TestFlight → wait for processing (5–20 min)
   - Add build to an internal or external group
   - External groups require export compliance answers before distribution

---

## Known App Store Connect rejection triggers

| Error | Cause | Fix |
|---|---|---|
| 90683 — Missing `NSMicrophoneUsageDescription` | KK's dictation code references mic APIs; App Store scans for these even if the app never uses them | Already fixed: `INFOPLIST_KEY_NSMicrophoneUsageDescription` in both Debug/Release build settings for ProtoType target in `project.pbxproj` |
| ITMS-90078 — Missing `NSExtensionAttributes` | Extension Info.plist missing `RequestsOpenAccess` | Already present in `PrototypeKeyboard/Info.plist` |
| 90535 — Invalid framework | KK embedded in wrong place | KK must be embedded in the host app only — see `ARCHITECTURE.md` |

---

## Keyboard not appearing after install

This is a silent failure — no crash log. Common causes:

1. **KK not embedded correctly.** The `.appex` loads KK from the host app's `Frameworks/` folder via rpath. If KK is missing from `ProtoType.app/Frameworks/`, dyld fails silently. Check: `ls Payload/ProtoType.app/Frameworks/` in the `.ipa`. `KeyboardKit.framework` must be there.

2. **User hasn't enabled the keyboard.** Settings → General → Keyboard → Keyboards → Add New Keyboard → Prototype.

3. **Open Access not granted.** Translation API calls need it. Settings → General → Keyboard → Keyboards → Prototype → Allow Full Access.

4. **To see runtime errors:** plug the device into a Mac, open Console.app, filter by process `PrototypeKeyboard`, reproduce the issue.

---

## CI

GitHub Actions workflow: `.github/workflows/ci.yml`

- Runs on push/PR to `main`
- macOS 15 runner, Xcode 16.3
- Builds for `generic/platform=iOS Simulator` (no named simulator needed)
- Tests run with `continue-on-error: true` (test target may not have a sim configured)
- Does **not** archive or upload — local Xcode steps above are required for TestFlight

---

## Branch rules

- Feature work goes on `claude/upbeat-newton-yUXN8` (or a new feature branch)
- **Never push to main or merge a PR without explicit "merge" instruction from the user**
- After merging, archive from the latest `main` commit
