# Release & client workflow

How to version, build, and hand off WhisperBack professionally.

---

## Repository layout

| Path | Purpose |
|------|---------|
| `mobile/` | Flutter app (source of truth for app version) |
| `dist/` | Local APK output (`whisperback-test.apk`) — **not committed** |
| `docs/qa-checklist.md` | Pre-release QA |
| `docs/APK_TESTING.md` | Phone install + test flows |
| `CHANGELOG.md` | Client-facing release notes |

---

## Version numbers

Edit `mobile/pubspec.yaml`:

```yaml
version: 1.0.0+1
#        │ │ │  └── build number (integer, bump every store/APK upload)
#        └─┴─┴──── semver (MAJOR.MINOR.PATCH)
```

| Bump | When |
|------|------|
| **PATCH** (`1.0.1`) | Bug fixes, small UI tweaks |
| **MINOR** (`1.1.0`) | New features, no breaking changes |
| **MAJOR** (`2.0.0`) | Breaking changes, large scope |
| **+BUILD** | Every client APK or store upload (Play Store requires monotonic build) |

After changing version, update `CHANGELOG.md` under `[Unreleased]` → move to dated section.

---

## Git branching

```
main          ← stable, client-ready; triggers CI + APK workflow
develop       ← integration (optional)
feature/*     ← your work (e.g. feature/schedule-ui)
fix/*         ← bug fixes (e.g. fix/playback-crash)
```

**Daily work**

```powershell
git checkout main
git pull
git checkout -b feature/my-change
# ... edit, test ...
git add .
git commit -m "Add playlist clip reorder"
git push -u origin feature/my-change
```

Open a PR to `main` on GitHub. **Mobile CI** runs analyze, test, and APK smoke build.

**Client builds** — only from `main` after QA passes (see below).

---

## Local quality gate (before every push)

From repo root:

```powershell
cd mobile
flutter pub get
dart format .
flutter analyze --no-fatal-infos
flutter test
```

Or use the setup script:

```powershell
.\scripts\setup_mobile.ps1
```

---

## Building an APK for the client

### Option A — GitHub Actions (recommended)

1. Merge to `main` and push
2. [Actions → Build Android APK](https://github.com/MaiMam01/whispherback/actions/workflows/build_apk.yml)
3. Download artifact **`whisperback-debug-apk`**
4. Rename for client: `WhisperBack-v1.0.0-build1-debug.apk`

### Option B — Local Windows

Prerequisites: `flutter doctor` all green, NDK installed (see `docs/APK_TESTING.md`).

```powershell
.\scripts\build_apk.ps1
# Output: dist\whisperback-test.apk
```

---

## Client handoff checklist

Before sending an APK or demo build:

- [ ] Version bumped in `pubspec.yaml` and noted in `CHANGELOG.md`
- [ ] `flutter test` passes locally or CI green on `main`
- [ ] QA checklist completed ([docs/qa-checklist.md](qa-checklist.md))
- [ ] APK tested on at least one physical Android device ([APK_TESTING.md](APK_TESTING.md))
- [ ] Email/message includes: version, date, what changed, known limits

**Example client message**

> WhisperBack **v1.0.0 (build 1)** — test APK attached  
> **Date:** 2026-06-02  
> **Changes:** Record/import clips, add to playlist, interval scheduling, playback modal  
> **Test:** Home → Active ON → record clip → add to playlist → schedule 5 min → wait for playback  
> **Note:** Debug build; no cloud sync yet (Phase 2)

---

## Git tags (optional, for milestones)

After a client-approved release on `main`:

```powershell
git tag -a v1.0.0 -m "Phase 1 MVP client demo"
git push origin v1.0.0
```

Create a GitHub Release from the tag and attach the APK artifact.

---

## What not to commit

- `mobile/build/`, `dist/*.apk`, `.env`, API keys
- Local Android SDK / NDK (machine-specific)
- `mobile/data/` or device databases

These are already in `.gitignore` where applicable.

---

## CI workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Mobile CI** | PR/push to `main`/`develop` | Format, analyze, test, APK smoke |
| **Build Android APK** | Push to `main`/`develop` + manual | Produces downloadable APK artifact |

Analyze uses `--no-fatal-infos` so style hints do not block APK builds; **warnings and errors still fail CI**.

---

## Phase 2 (later)

- `staging` flavor + internal track (Play Internal / TestFlight)
- Signed release APK/AAB with keystore in GitHub Secrets
- Semantic versioning aligned with store listings

See [api-contracts.md](api-contracts.md) and [INSTALLATION.md](INSTALLATION.md).
