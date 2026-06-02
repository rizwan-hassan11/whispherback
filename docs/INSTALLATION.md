# WhisperBack — Development Environment Installation

Complete setup guide for **any new PC or laptop** (Windows, macOS, Linux). Use this together with [MOBILE_WALKTHROUGH.md](MOBILE_WALKTHROUGH.md) to understand the app after install.

---

## Is the app built from scratch?

**No.** WhisperBack is already a **substantial Flutter MVP (~45% toward release)**:

| Done | Not done yet (see [PROJECT_AUDIT.md](PROJECT_AUDIT.md)) |
|------|-----------------------------------------------------------|
| 13+ screens, routing, glass UI theme | Client sign-off polish on S02, S04, S08, S13 |
| SQLite + repositories | Full background audio / lock screen |
| Playback coordinator, scheduler, shuffle | Cloud sync (Phase 2) |
| Sleep & prayer modes (offline) | Store submission (TestFlight / Play) |
| Approved HTML design reference | Some features unwired (notifications, limits) |

You **continue this codebase**—you do **not** restart in a new framework or empty repo.

---

## What you must install

| Component | Required? | Purpose |
|-----------|-----------|---------|
| **Git** | Yes | Clone repo |
| **Flutter SDK (stable)** | Yes | Mobile framework + Dart |
| **Android Studio** | Yes for **Android** phone/emulator | Android SDK, emulator, licenses |
| **Xcode** | Mac only, for **iOS** | iPhone builds |
| **VS Code** or Android Studio | Recommended | Editor |
| **Gradle** | **No** (bundled) | Android builds via Flutter |
| **Node.js** | Only for `admin/` / `infra/` | Not needed for mobile-only |

---

## 1. Clone the repository

```bash
git clone https://github.com/MaiMam01/whispherback.git
cd whispherback
```

If you already have the folder locally, `git pull` to update.

---

## 2. Install Flutter

### Windows

1. Download: [https://docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows)  
   Prefer the **official installer** (not a shallow `git clone`) if your network is unstable.
2. Ensure `flutter` is on PATH (open a **new** PowerShell after install).
3. Verify:

```powershell
flutter --version
flutter doctor -v
```

### macOS

1. [https://docs.flutter.dev/get-started/install/macos](https://docs.flutter.dev/get-started/install/macos)  
2. Install Xcode from the App Store (for iOS).
3. `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
4. `sudo xcodebuild -runFirstLaunch`

### Linux

1. [https://docs.flutter.dev/get-started/install/linux](https://docs.flutter.dev/get-started/install/linux)  
2. Install build deps (Debian/Ubuntu example):

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev
```

**Version:** Use Flutter **3.24+** (stable channel). Project uses Dart **3.5+**.

---

## 3. Install editor (optional but recommended)

### VS Code

1. Install [VS Code](https://code.visualstudio.com/).
2. Extensions: **Flutter**, **Dart**.

### Android Studio

1. Install [Android Studio](https://developer.android.com/studio).
2. Plugins: **Flutter**, **Dart**.

---

## 4. Android setup (phones & emulators)

Required for Android builds. Skip only if you develop on **Windows desktop** or **Chrome** temporarily.

### 4.1 Install Android Studio

- Windows: run installer, include **Android SDK**, **Android SDK Platform**, **Android Virtual Device**.

### 4.2 SDK & licenses

1. Open Android Studio → **SDK Manager**:
   - **SDK Platforms:** latest stable (e.g. API 35)
   - **SDK Tools:** Android SDK Build-Tools, Platform-Tools, Emulator
2. In terminal:

```powershell
flutter doctor --android-licenses
```

Accept all licenses.

### 4.3 Custom SDK path (if needed)

If SDK is not in the default location:

```powershell
flutter config --android-sdk "C:\Users\YOUR_USER\AppData\Local\Android\Sdk"
```

### 4.4 Emulator

1. Android Studio → **Device Manager** → **Create Virtual Device** → Pixel-class phone.
2. List devices:

```powershell
flutter devices
```

### 4.5 Physical Android phone

1. Enable **Developer options** → **USB debugging**.
2. Connect USB → allow debugging on phone.
3. `flutter devices` should list the device.

---

## 5. iOS setup (macOS only)

1. Install **Xcode** from App Store.
2. `cd mobile/ios && pod install` (first time; Flutter may run this automatically).
3. Open `ios/Runner.xcworkspace` in Xcode once to trust signing (use your Apple ID for development).
4. Simulator: `open -a Simulator`, then `flutter run`.

**Windows/Linux cannot build for iOS locally**—use a Mac or cloud CI (Codemagic, GitHub macOS runner).

---

## 6. Project bootstrap (every new machine)

From the **repository root**:

### Windows (automated)

```powershell
.\scripts\setup_mobile.ps1
```

### Manual (all platforms)

```bash
cd mobile

# Generate android/, ios/, windows/, web/ if missing from git
flutter create . --project-name whisperback --org com.whisperback

flutter pub get
flutter analyze
flutter test
```

**Note:** `android/` and `ios/` are generated locally. They may be gitignored or committed depending on team policy—if missing, always run `flutter create .` once.

---

## 7. Run the app

```bash
cd mobile
flutter devices
```

Pick a target:

| Target | Command | When to use |
|--------|---------|-------------|
| Android emulator/phone | `flutter run --dart-define=FLAVOR=dev` | Primary mobile dev |
| Windows desktop | `flutter run -d windows --dart-define=FLAVOR=dev` | No Android SDK yet |
| Chrome (web) | `flutter run -d chrome --dart-define=FLAVOR=dev` | Quick UI check (not all plugins work on web) |
| iOS Simulator | `flutter run -d ios --dart-define=FLAVOR=dev` | macOS only |

**Hot reload:** press `r` in the terminal while running. **Hot restart:** `R`.

### Open design reference (no Flutter needed)

```powershell
# Windows
start ..\design\ui-preview.html

# macOS
open ../design/ui-preview.html
```

---

## 8. Verify everything works

```bash
cd mobile
flutter doctor -v          # All checkmarks you need for your target platform
flutter analyze            # No "error" lines
flutter test               # All tests pass
flutter build apk --debug --dart-define=FLAVOR=dev   # Android smoke (needs SDK)
```

On Windows without Android SDK:

```powershell
flutter build windows --debug --dart-define=FLAVOR=dev
```

---

## 9. Environment variables & flavors

| Variable | How | Purpose |
|----------|-----|---------|
| `FLAVOR` | `--dart-define=FLAVOR=dev` | dev / staging / prod (convention) |

Example:

```bash
flutter run --dart-define=FLAVOR=dev
```

---

## 10. Troubleshooting

### `Unable to locate Android SDK`

- Install Android Studio and SDK Manager packages (section 4).
- `flutter config --android-sdk <path>`
- Re-run `flutter doctor -v`.

### `intl` / version solving failed

Project requires `intl: ^0.20.2` (Flutter 3.38+). Run:

```bash
flutter pub get
```

### `databaseFactory not initialized` in tests

Tests use `test/flutter_test_config.dart` with `sqflite_common_ffi`. Run tests from `mobile/`:

```bash
flutter test
```

### `flutter create` overwrote my files

`flutter create .` in an existing project only adds **missing** platform folders; it should not delete `lib/`. If in doubt, use git to review changes.

### Analyzer warnings (trailing commas, etc.)

Non-blocking infos may remain. **Errors must be zero** before release. Run:

```bash
flutter analyze
```

### Emulator slow or HAXM

Enable virtualization in BIOS (Intel VT-x / AMD-V). Use a **x86_64** system image with Google APIs.

### Microphone / location on device

Android permissions are in `android/app/src/main/AndroidManifest.xml`.  
iOS usage strings are in `ios/Runner/Info.plist`.  
The app must request runtime permission via `permission_handler` when using Record or Prayer GPS.

### First launch shows empty playlists

Expected: seed creates **Morning Whispers** and **Work Focus** with **no clips** (add via Record/Import). Older builds used fake `demo://` paths that could not play.

---

## 11. CI (GitHub Actions)

Workflow: `.github/workflows/mobile_ci.yml`

On push to `mobile/`:

- `flutter pub get`
- `dart format` check
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`

Match this locally before opening a PR.

---

## 12. Checklist — new laptop

Copy and tick off:

```
[ ] Git installed
[ ] Flutter stable installed, on PATH
[ ] flutter doctor -v — fix all ❌ for your target (Android and/or iOS)
[ ] Repo cloned
[ ] cd mobile && flutter pub get
[ ] flutter create .  (if android/ missing)
[ ] .\scripts\setup_mobile.ps1  OR manual analyze + test
[ ] flutter run -d <device>
[ ] Opened design/ui-preview.html for UI reference
[ ] Read docs/MOBILE_WALKTHROUGH.md
```

---

## 13. What not to install for mobile-only work

- **Gradle** (standalone)
- **CocoaPods** (global) — Flutter invokes it for iOS when needed
- **Node.js** — unless working on `admin/` or `infra/`
- **AWS CLI** — Phase 2 infra only
- **React Native / Expo** — wrong stack

---

## Related docs

| Doc | Content |
|-----|---------|
| [**LOCAL_DEVELOPMENT.md**](LOCAL_DEVELOPMENT.md) | **Hot reload on phone, APK size, daily workflow** |
| [MOBILE_WALKTHROUGH.md](MOBILE_WALKTHROUGH.md) | Architecture, screens, learning path |
| [PROJECT_AUDIT.md](PROJECT_AUDIT.md) | Gaps and sprint plan |
| [mobile/README.md](../mobile/README.md) | Short commands |
| [design/screen-specs.md](../design/screen-specs.md) | UI requirements |

---

*Update this file when minimum Flutter version or platform requirements change.*
