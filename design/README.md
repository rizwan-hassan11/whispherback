# WhisperBack Design System

## Interactive preview (no Flutter required)

Open **[ui-preview.html](ui-preview.html)** in your browser — v3 with **light/dark theme toggle**, **Sign In / Sign Up** screens, glass UI, and all main app screens.

## Figma

Create a Figma file matching [screen-specs.md](screen-specs.md) and link here:

`[Figma — WhisperBack v1]` _(add URL when file is created)_

## Tokens

Machine-readable tokens for Flutter theming: [tokens.json](tokens.json)

## Components (library checklist)

| Component | Used on | Notes |
|-----------|---------|-------|
| ActiveToggle | S02 Home | Gradient power button, pulse rings when ON |
| GlassNavBar | Shell | Floating blurred nav; labels optional |
| WhisperCard | S03, S05 | Glass cards with badges + progress |
| ScheduleConflictDialog | S08 modal | Blocks save, names conflicting playlist |
| PlaybackModal | S13 | Bottom sheet with art + scrubber |
| ProgressBar | S07 Import | Real-time import progress |
| SleepTimer | S10 | Countdown + end early |
| PrayerMethodPicker | S11 | Method + madhab dropdowns |
| StatusChip | S02 | Sleep/prayer active indicator |

## Client sign-off (required before pixel-perfect polish)

- [ ] S02 Home — Active toggle
- [ ] S04 Playlist detail
- [ ] S08 Schedule builder
- [ ] S13 Playback modal
