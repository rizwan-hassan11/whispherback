# Changelog

All notable releases of WhisperBack are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/). Version numbers match `mobile/pubspec.yaml` (`version: MAJOR.MINOR.PATCH+BUILD`).

## [Unreleased]

### Added
- Local dev guide and `run_android.ps1` (USB hot reload)
- App bootstrap: parallel DB + font preload; cached list providers
- APK build scripts and GitHub Actions workflow
- Installation and APK testing documentation

### Added
- Interactive drifting particle background (home + premium screens)

### Fixed
- Recorded/imported clips now play when tapped (play button was a no-op)
- Schedule builder and other sub-pages open full-screen above the nav bar
  (Save button is no longer hidden behind the bottom bar)
- Double input-field borders removed (global borderless decoration)
- Light-mode: removed grey scrim over the bottom nav bar; softened shadow
- Neon-blue treatment for clip/record/schedule icons and buttons so they are
  visible in light mode (previously white/grey accents disappeared)
- Bed (Sleep) button on Home is now a glowing neon control, always visible
- Android blank screen: shell body layout + font preload + INTERNET permission
- Android Gradle: NDK 28.2 and core library desugaring (GitHub APK build)
- Analyzer warnings blocking CI (unused imports, playback coordinator)
- Schedule engine skips firing during manual playback

## [1.0.0+1] — 2026-06-01

### Added
- Phase 1 local MVP: playlists, clips, record/import, scheduling, sleep & prayer modes
- Active/inactive master toggle and playback modal

[Unreleased]: https://github.com/MaiMam01/whispherback/compare/v1.0.0...main
[1.0.0+1]: https://github.com/MaiMam01/whispherback/releases/tag/v1.0.0
