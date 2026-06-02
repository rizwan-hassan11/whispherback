# WhisperBack — Android APK testing guide

Use this to install the app on a real phone and test **record → playlist → schedule → playback**.

---

## 1. Build the APK (on your PC)

**One-time:** Android SDK must be set up (`flutter doctor` shows ✓ Android toolchain).

### Prerequisites (Windows)

| Requirement | Check | Fix |
|-------------|-------|-----|
| Flutter | `flutter doctor` | [INSTALLATION.md](INSTALLATION.md) |
| JDK 17 | `java -version` | `winget install Microsoft.OpenJDK.17` |
| Android NDK | folder under `%LOCALAPPDATA%\Android\Sdk\ndk\` must contain `source.properties` | see **NDK troubleshooting** below |

The build script auto-finds JDK 17 if `JAVA_HOME` is not set.

From repo root:

```powershell
.\scripts\build_apk.ps1
```

Output file:

```text
whispherback\dist\whisperback-test.apk
```

### NDK troubleshooting (common on Windows)

If the build fails with **`did not have a source.properties file`**, the NDK download was interrupted (not an app bug):

```powershell
# Remove broken partial install
Remove-Item "$env:LOCALAPPDATA\Android\Sdk\ndk\*" -Recurse -Force -ErrorAction SilentlyContinue

# Option A — let Gradle re-download (run build, wait 10–20 min on stable Wi-Fi)
.\scripts\build_apk.ps1

# Option B — manual NDK install (~714 MB)
.\scripts\install_ndk.ps1
.\scripts\build_apk.ps1
```

### Option C — GitHub Actions (no local NDK)

After pushing to `main`, GitHub builds the APK in the cloud:

1. Open [Actions → Build Android APK](https://github.com/MaiMam01/whispherback/actions/workflows/build_apk.yml)
2. Open the latest green run → **Artifacts** → download `whisperback-debug-apk`
3. Rename `app-debug.apk` if needed, copy to your phone, install

Manual build:

```powershell
cd whispherback\mobile
flutter build apk --debug --dart-define=FLAVOR=dev
```

APK path:

```text
mobile\build\app\outputs\flutter-apk\app-debug.apk
```

---

## 2. Install on your phone

**If the screen looks blank (only bottom bar visible):** uninstall the old APK, install the latest build from GitHub Actions (fix in `main` after June 2026). On first launch, use **Wi‑Fi** so display fonts can download (~2 MB).

### Option A — Copy APK to phone (easiest)

1. Copy `dist\whisperback-test.apk` to the phone (USB, email, Google Drive, etc.).
2. On the phone, open the file.
3. Allow **Install unknown apps** for your file manager if prompted.
4. Tap **Install**.

### Option B — USB debugging

```powershell
adb install -r whispherback\dist\whisperback-test.apk
```

---

## 3. Test the core flow (record → schedule → whisper)

### Step 1 — Turn app ON

1. Open **WhisperBack**.
2. On **Home**, tap the large **Active** toggle until it glows (ON).
3. Scheduling only runs when the app is **Active**.

### Step 2 — Record or import audio

1. Bottom nav → **Clips**.
2. Tap **Record** → allow microphone → record → **Stop and save**.
3. Or tap **Import** → pick an MP3/M4A file.

### Step 3 — Create a playlist and add clips

1. **Playlists** → open **Morning Whispers** (or **New playlist**).
2. Tap **Add clips**.
3. Select your clip(s) → **Add N clip(s)**.

### Step 4 — Schedule the playlist

1. On playlist detail, tap the **schedule** icon (top right), or **Schedule** in actions.
2. Set **Start time** to a few minutes from now (e.g. now + 3 min).
3. Set **End time** a few hours ahead.
4. Pick interval **5 min** (for a quick test) or **15–30 min**.
5. Tap **Save schedule**.
6. Message reminds you to keep the app **Active** on Home.

### Step 5 — Wait for scheduled playback

- With app **Active**, a clip should play within about **30 seconds** of each interval boundary (Android).
- You should see the **playback modal** and hear audio.
- Check **Schedule** tab for your saved plan.

### Quick manual test (no waiting)

1. Home → **Active ON**.
2. Playlist with clips → **Play all**.
3. Confirms audio files and playback work.

---

## 4. Permissions on first use

| Feature | Permission |
|---------|------------|
| Record clip | Microphone |
| Import | Storage / files |
| Prayer mode | Location (optional) |
| Notifications | Post notifications (Android 13+) |

---

## 5. Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails on NDK | Delete `%LOCALAPPDATA%\Android\Sdk\ndk\28.2.13676358` and run `.\scripts\build_apk.ps1` again |
| Schedule does not fire | App must be **Active**; check start/end time and interval; keep app open or in background |
| No sound on play | Add clips to playlist first; re-record if file missing |
| Install blocked | Settings → allow install from unknown sources |

---

## 6. What works on phone vs Windows desktop

| Feature | Android phone | Windows desktop |
|---------|---------------|-----------------|
| UI / navigation | ✓ | ✓ |
| SQLite / playlists | ✓ | ✓ |
| Record / import | ✓ | Limited |
| Scheduled whispers | ✓ (best on device) | Partial |
| Prayer GPS | ✓ | Limited |

For client demos of **scheduling**, use the **Android APK** on a real device.
