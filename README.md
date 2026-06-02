# WhisperBack

**Your Personalized Audio Whisperer** — cross-platform mobile app for scheduled personal audio playback, sleep mode, and offline prayer-aware silence.

## Repository structure

```
whispherback/
├── mobile/          Flutter app (iOS + Android) — Phase 1 local MVP
├── api/             REST API (local dev + contract reference) — Phase 2
├── admin/           Next.js admin dashboard — Phase 2
├── infra/           AWS infrastructure (CDK) — Phase 2
├── design/          Design tokens, screen specs, Figma exports
├── docs/            Architecture, playback states, API contracts, QA
└── documents/       Client proposals and feature specifications
```

## Tech stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter 3.x, Riverpod, sqflite (SQLite) |
| Audio | just_audio, audio_service |
| Prayer times | adhan (offline, on-device GPS) |
| Backend (Phase 2) | AWS Cognito, DynamoDB, S3, Lambda, API Gateway |
| Admin (Phase 2) | Next.js on AWS Amplify |
| CI/CD | GitHub Actions, Fastlane |

## Quick start — mobile

### Develop on phone (hot reload — no APK each time)

```powershell
.\scripts\run_android.ps1
```

Edit code → save → press **`r`** in the terminal. See [docs/LOCAL_DEVELOPMENT.md](docs/LOCAL_DEVELOPMENT.md).

### Prerequisites

- Flutter SDK 3.24+ ([install guide](https://docs.flutter.dev/get-started/install))
- Android Studio / Xcode for device builds
- Node.js 20+ (API, admin panel, Phase 2)

### Setup

```bash
cd mobile
flutter pub get
# First time only, if android/ is missing:
flutter create . --project-name whisperback --org com.whisperback
flutter run --dart-define=FLAVOR=dev
```

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for full setup on a new machine.

### Flavors

| Flavor | Purpose |
|--------|---------|
| `dev` | Local development, debug logging |
| `staging` | Internal TestFlight / Play Internal |
| `prod` | Store release |

```bash
flutter run --dart-define=FLAVOR=dev
```

## Phase 1 scope (local MVP)

- Active/Inactive master toggle
- Playlists, clip library, record & import
- Interval scheduling with conflict detection
- Shuffle (per-playlist + global)
- Sleep Mode & Prayer Mode (offline Adhan)
- Popup playback modal
- Fully offline — no account required

## Quick start — API (Phase 2 dev)

```bash
cd api
cp .env.example .env
npm install
npm run dev
```

See [api/README.md](api/README.md). Endpoints match [docs/api-contracts.md](docs/api-contracts.md).

## Phase 2 scope

- AWS cloud sync (Premium)
- Cognito authentication
- Admin dashboard
- App Store / Play Store submission automation

## Documentation

- [**Local development (hot reload, APK size)**](docs/LOCAL_DEVELOPMENT.md)
- [**Installation (new PC / laptop)**](docs/INSTALLATION.md) — Flutter, Android Studio, commands, checklist
- [**Mobile walkthrough**](docs/MOBILE_WALKTHROUGH.md) — Architecture, design → code, learning path
- [Project audit (May 2026)](docs/PROJECT_AUDIT.md)
- [Playback state diagram](docs/playback-states.md)
- [Screen specifications](design/screen-specs.md)
- [Design tokens](design/tokens.json)
- [API contracts (Phase 2)](docs/api-contracts.md)
- [**Release & client workflow**](docs/RELEASE_WORKFLOW.md)
- [**API server (run locally)**](api/README.md)
- [QA checklist](docs/qa-checklist.md)

## GitHub

Remote: [https://github.com/MaiMam01/whispherback](https://github.com/MaiMam01/whispherback)

```bash
git remote add origin https://github.com/MaiMam01/whispherback.git
git push -u origin main
```

## License

Proprietary — FOUS Ventures / Dr. Maria. All rights reserved.
