# Local development — run on your phone without reinstalling APKs

Use **`flutter run`** while coding. Changes apply in seconds via **hot reload** — no GitHub Actions, no 177 MB APK download each time.

---

## Daily workflow

```
edit code  →  save  →  press r in terminal (hot reload)  →  see fix on phone
       ↓
when stable  →  git push  →  GitHub builds APK for client/testing
```

| Task | Command |
|------|---------|
| Run on phone (USB) | `.\scripts\run_android.ps1` |
| Run on Windows desktop | `cd mobile && flutter run -d windows` |
| Analyze + test | `.\scripts\setup_mobile.ps1` |
| Client test APK | GitHub Actions → **Build Android APK** artifact |

See also [RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md) for versioning and client handoff.

---

## One-time: phone setup (USB debugging)

1. **Developer options** — Settings → About phone → tap **Build number** 7 times  
2. **USB debugging** — Settings → Developer options → USB debugging **ON**  
3. Connect USB cable → on phone tap **Allow** when prompted  
4. On PC:

```powershell
adb devices
# Should show: XXXXX    device
```

If `adb` is not found, use Android SDK platform-tools (`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`) or install [Android Studio](https://developer.android.com/studio).

---

## Run the app on your phone

From repo root:

```powershell
.\scripts\run_android.ps1
```

List devices:

```powershell
.\scripts\run_android.ps1 -ListDevices
.\scripts\run_android.ps1 -DeviceId YOUR_DEVICE_ID
```

While the app is running:

| Key | Action |
|-----|--------|
| **r** | Hot reload (UI/logic — fast) |
| **R** | Hot restart (full app restart) |
| **q** | Quit |

First run compiles native code (~2–5 min). Later runs are much faster.

---

## When to use APK vs `flutter run`

| Method | When |
|--------|------|
| **`flutter run`** | Every day while fixing bugs and UI |
| **Debug APK (CI)** | Share with tester who has no PC; smoke test release pipeline |
| **Release APK** | Closer to store size/performance; before client demo |

---

## APK size: is 177 MB OK?

**For a debug APK from CI — yes, that's normal.** Flutter debug builds are large because they include:

- Debug symbols and extra checks  
- **All CPU architectures** in one “fat” APK (arm64 + arm32 + x86…)  
- Unoptimized Dart snapshot  

**Typical sizes for this app:**

| Build | Approx. size |
|-------|----------------|
| Debug APK (CI, fat) | **150–200 MB** ← what you have |
| Release APK (single ABI) | **25–45 MB** |
| Release split per ABI | **~20–35 MB each** |
| Play Store AAB | Google delivers one ABI per device (~25 MB download) |

Smaller client test build (local or CI):

```powershell
cd mobile
flutter build apk --release --split-per-abi --dart-define=FLAVOR=dev
# Outputs: build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (~smaller)
#          app-arm64-v8a-release.apk  ← use this on most modern phones
```

Most phones from the last ~8 years use **arm64-v8a**.

---

## Performance & caching (built into the app)

| Optimization | What it does |
|--------------|----------------|
| **App bootstrap** | Opens SQLite + seeds + fonts once at startup (parallel) |
| **Riverpod `keepAlive`** | Playlists/clips/schedules stay cached when switching tabs |
| **`ref.invalidate(...)`** | Refreshes cache after record/import/save |
| **Google Fonts cache** | After first Wi‑Fi launch, fonts stored on device |
| **Singleton DB** | One SQLite connection for the session |

First launch on Android needs **Wi‑Fi once** for fonts (~2 MB). After that, offline is fine.

---

## Troubleshooting

### Phone not listed

- Try another USB cable (data-capable)  
- Revoke USB debugging authorizations on phone, reconnect  
- `adb kill-server` then `adb devices`

### Blank screen on device

- Uninstall old APK, use latest `main` build  
- First launch on Wi‑Fi  
- See [APK_TESTING.md](APK_TESTING.md)

### NDK / Gradle errors locally

- `.\scripts\install_ndk.ps1` then `.\scripts\build_apk.ps1`  
- Or use **`flutter run`** — Gradle manages NDK similarly to CI

### Hot reload did not apply change

- Press **R** (full restart)  
- Native/plugin changes require restart or full rebuild

---

## Related

- [INSTALLATION.md](INSTALLATION.md) — full machine setup  
- [APK_TESTING.md](APK_TESTING.md) — install APK + test flows  
- [RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md) — git, versions, client builds  
