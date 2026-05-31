# WhisperBack

**Your Personalized Audio Whisperer** — cross-platform mobile app for scheduled personal audio playback, sleep mode, and offline prayer-aware silence.

## Repository structure

```
whispherback/
├── mobile/          Flutter app (iOS + Android) — Phase 1 local MVP
├── admin/           Next.js admin dashboard — Phase 2
├── infra/           AWS infrastructure (CDK) — Phase 2
├── design/          Design tokens, screen specs, Figma exports
├── docs/            Architecture, playback states, API contracts, QA
└── documents/       Client proposals and feature specifications
```

## Tech stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter 3.x, Riverpod, Drift (SQLite) |
| Audio | just_audio, audio_service |
| Prayer times | adhan (offline, on-device GPS) |
| Backend (Phase 2) | AWS Cognito, DynamoDB, S3, Lambda, API Gateway |
| Admin (Phase 2) | Next.js on AWS Amplify |
| CI/CD | GitHub Actions, Fastlane |

## Quick start — mobile

### Prerequisites

- Flutter SDK 3.24+ ([install guide](https://docs.flutter.dev/get-started/install))
- Android Studio / Xcode for device builds
- Node.js 20+ (admin panel, Phase 2)

### Setup

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

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

## Phase 2 scope

- AWS cloud sync (Premium)
- Cognito authentication
- Admin dashboard
- App Store / Play Store submission automation

## Documentation

- [Project audit (May 2026)](docs/PROJECT_AUDIT.md)
- [Playback state diagram](docs/playback-states.md)
- [Screen specifications](design/screen-specs.md)
- [Design tokens](design/tokens.json)
- [API contracts (Phase 2)](docs/api-contracts.md)
- [QA checklist](docs/qa-checklist.md)

## GitHub

Remote: [https://github.com/MaiMam01/whispherback](https://github.com/MaiMam01/whispherback)

```bash
git remote add origin https://github.com/MaiMam01/whispherback.git
git push -u origin main
```

## License

Proprietary — FOUS Ventures / Dr. Maria. All rights reserved.
