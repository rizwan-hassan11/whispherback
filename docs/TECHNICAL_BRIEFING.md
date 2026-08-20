# WhisperBack — Technical Briefing

**Audience:** an external Flutter developer reviewing the app for advice and QA.
**Repo:** `whispherback/mobile` · **Package:** `whisperback` · **App ID:** `com.whisperback.whisperback`

---

## 0. The one-paragraph summary

WhisperBack is an **offline-first, Android-first scheduled audio app**. Users record or import short audio clips ("whispers"), group them into playlists, and attach a schedule to a playlist. When a scheduled time arrives, the clip plays — even if the app is closed and the phone is asleep.

The single most important architectural fact: **on Android, scheduled playback does not run through Flutter at all.** Dart computes *when* clips should play and hands a JSON snapshot to Kotlin. Native Android `AlarmManager` + a foreground service with `MediaPlayer` do the actual playing. Dart only mirrors state back into the UI.

Everything else in the design follows from that split.

---

## 1. First principles: why the architecture looks like this

### The product requirement
> "The clip must play at the scheduled time, reliably, even when the app is closed, on any Android phone."

### Why that is hard on modern Android

| Constraint | Effect |
|---|---|
| **Doze mode** (Android 6+) | Background timers are batched and deferred, sometimes by hours |
| **Background execution limits** (Android 8+) | Background services are killed within minutes |
| **Background start restrictions** (Android 12+) | You cannot start a foreground service from the background without a valid exemption |
| **Foreground service types** (Android 14+) | Audio playback requires `foregroundServiceType="mediaPlayback"` and a matching permission |
| **OEM battery killers** | Xiaomi, Vivo, Oppo, Samsung, Realme, Infinix each add their own process reaper on top of stock Android |

### Approaches that were tried and rejected

| Approach | Why it failed |
|---|---|
| Dart `Timer.periodic` in the app process | Dies as soon as the OS reclaims the process |
| `android_alarm_manager_plus` (background isolate) | Its periodic alarms are **inexact** (Doze-throttled), and a background isolate **cannot acquire audio focus** on Android 14+ — audio silently never plays. Removed in Round 21 (see the comment block in `pubspec.yaml` lines 28–38) |
| `WorkManager` | 10-minute minimum interval, deferred during Doze — unusable for "play at 7:00 PM exactly" |
| `setExactAndAllowWhileIdle` | Throttled to ~9-minute minimums on Android 12+ for non-alarm-clock alarms |

### The approach that works: the alarm-clock model

`AlarmManager.setAlarmClock()` is the highest-reliability scheduling primitive Android offers. It is what the Clock app uses. It gives us three things nothing else does:

1. **Doze exemption** — the device briefly wakes before the alarm fires
2. **A temporary background foreground-service-start grant** on Android 12+ — this is what legally lets us start an audio service from a `BroadcastReceiver`
3. **OEM respect** — aggressive OEMs generally do not kill alarm-clock alarms, because doing so would break the user's morning alarm

So the chain became: **exact alarm → broadcast receiver → typed media foreground service → `MediaPlayer`.** All in Kotlin, no Flutter engine required.

---

## 2. Tech stack

### Language and framework
- **Flutter** (Dart SDK `>=3.5.0 <4.0.0`), Material 3
- **Kotlin** for the Android native layer (JVM target 17)
- **Swift** — iOS is scaffold only (see §11)

### Key packages

| Package | Version | What it does here |
|---|---|---|
| `flutter_riverpod` | ^2.6.1 | State management / DI (no code generation) |
| `go_router` | ^14.6.2 | Declarative routing with a shell route for the nav bar |
| `sqflite` | ^2.4.1 | Local SQLite database (the only persistence for domain data) |
| `sqflite_common_ffi` + `sqlite3` | ^2.3.4 / ^3.3.3 | Runs SQLite in unit tests on desktop/CI |
| `shared_preferences` | ^2.3.3 | Small key/value state (settings, last-fired timestamps) |
| `just_audio` | ^0.9.42 | ExoPlayer wrapper — **in-app manual playback only** |
| `audio_service` | ^0.18.17 | MediaSession, lock-screen controls, media foreground service |
| `audio_session` | ^0.1.21 | Audio focus + interruption handling |
| `record` | ^5.2.0 | Microphone capture (AAC-LC 44.1 kHz mono → `.m4a`) |
| `file_picker` | ^8.1.6 | Audio import |
| `flutter_local_notifications` | ^18.0.1 | Status card, schedule reminders, prayer reminders |
| `timezone` + `flutter_timezone` | ^0.10.0 / ^4.1.0 | Timezone-correct notification scheduling |
| `permission_handler` | ^11.3.1 | Runtime permissions |
| `adhan` + `geolocator` | ^2.0.0 / ^13.0.2 | Prayer-time calculation (**feature-flagged off**) |
| `google_fonts`, `flutter_svg`, `flutter_lucide` | — | Typography, vector assets, icon set |
| `uuid`, `equatable`, `collection`, `intl` | — | Utilities |

**No code generation anywhere.** No `build_runner`, no `freezed`, no `*.g.dart`, no `riverpod_generator`. All value objects hand-roll `copyWith` and use `equatable` for equality.

### Android toolchain
- AGP **8.11.1**, Kotlin **2.2.20**, Gradle wrapper **8.14**
- `compileSdk 36`, `targetSdk 36`, `minSdk 24` (Android 7.0+)
- Java 17 with core library desugaring (`desugar_jdk_libs:2.1.4`)
- `androidx.media:media:1.7.0` pinned explicitly for `MediaStyle` notifications

---

## 3. Folder structure

```
mobile/
├─ lib/                     100 Dart files
├─ test/                    46 test files + global harness
├─ integration_test/        1 launch smoke test
├─ android/                 real native layer, 6 Kotlin files
├─ ios/                     Flutter scaffold only
├─ linux/ macos/ web/ windows/   untouched scaffolds (desktop used only to run unit tests)
├─ assets/                  icons/, audio/adhan.mp3, branding/app_logo.png
├─ pubspec.yaml
└─ analysis_options.yaml    flutter_lints + avoid_print
```

### `lib/` — layered by responsibility

```
lib/
├─ main.dart          entrypoint: crash net, AudioService.init, ProviderScope
├─ app.dart           MaterialApp.router, lifecycle observer, notification bootstrap
│
├─ core/              cross-cutting, no business logic
│  ├─ bootstrap/      one-shot DB open + seed + orphan file sweep
│  ├─ config/         feature_flags.dart
│  ├─ constants/      tier caps, tolerances
│  ├─ errors/         exception → localized string mapping
│  ├─ layout/         responsive breakpoints, root snackbar key
│  ├─ router/         GoRouter config
│  ├─ theme/          colors, radii, icons, playlist cover gradients
│  ├─ ux/             haptics helper
│  └─ widgets/        13 shared widgets (shell, nav bars, dialogs, banners)
│
├─ domain/            pure value objects + enums, zero dependencies
│  ├─ entities/       AudioClip, Playlist, PlaybackSchedule, SleepWindow
│  └─ playback/       AppPlaybackState, PlaybackSnapshot
│
├─ data/              persistence
│  ├─ database/       database_helper.dart (schema + migrations), seed_service.dart
│  └─ repositories/   6 repositories — the ONLY code that touches SQL
│
├─ services/          behaviour / orchestration
│  ├─ audio/          WhisperAudioHandler, recording, import, path guard
│  ├─ playback/       PlaybackCoordinator ← the app's hub
│  ├─ scheduler/      6 files — the scheduling brain
│  ├─ notifications/  NotificationService + notification_sync
│  ├─ platform/       keep-alive channel, runtime permissions
│  ├─ prayer/         adhan (feature-flagged off)
│  └─ shuffle/        Fisher–Yates with cycle tracking
│
├─ providers/         3 files — ALL Riverpod providers live here
├─ features/          14 feature folders (screens + local widgets)
└─ l10n/              hand-written localization, 6 languages
```

**The dependency rule:** `features` → `providers` → `services` → `data` → `domain`. `domain` depends on nothing. `core` is available to everyone.

---

## 4. Data layer

### Database

Defined entirely in `lib/data/database/database_helper.dart`. Singleton, file `whisperback.db`, **schema version 5**, `PRAGMA foreign_keys = ON` (the schema relies on `ON DELETE CASCADE`).

| Table | Key columns | Notes |
|---|---|---|
| `clips` | `id` PK, `title`, `file_path`, `duration_ms`, `created_at`, `source` | `source` = `recorded` \| `imported` |
| `playlists` | `id` PK, `name` **UNIQUE**, timestamps, `shuffle_enabled`, `is_favourite` | |
| `playlist_clips` | PK `(playlist_id, clip_id)`, `sort_order` | Both FKs CASCADE |
| `schedules` | `id` PK, `playlist_id` **UNIQUE**, `start_time`, `end_time?`, `interval_minutes`, `days_mask`, `enabled`, `alarm_enabled`, `shuffle_enabled` | One schedule per playlist. FK CASCADE |
| `sleep_windows` | `id` PK, start/end, `label`, `active` | |
| `prayer_settings` | singleton row via `CHECK (id = 1)` | |
| `app_state` | singleton row via `CHECK (id = 1)`: `is_active`, `global_shuffle_enabled` | The master Active toggle |

**Migrations** (`onUpgrade`): v2 added `end_time`/`alarm_enabled`/`days_mask`; v3 added `play_adhan`; v4 zeroed `play_adhan` (adhan shelved); v5 added `is_favourite`.

**No explicit indices.** Justified by the tier caps (≤50 playlists, ≤50 clips each) — worth revisiting if the data model grows.

### Derived (not stored) fields

Two important columns are computed by SQL joins at read time, not persisted:
- `Playlist.clipCount` / `totalDurationMs` / `hasSchedule`
- `PlaybackSchedule.playlistDurationMs` = `SUM(clips.duration_ms)` for the schedule's playlist

That second one matters enormously for scheduling — see §7.

### Repositories

| Repository | Responsibility |
|---|---|
| `ClipRepository` | Clip CRUD; owns **duration backfill** (native probe → `just_audio` fallback) and broadcasts `onDurationBackfilled` |
| `PlaylistRepository` | Playlists + join table; enforces tier limits; transactional reorder; refuses delete when an enabled schedule exists |
| `ScheduleRepository` | Schedules + the **conflict engine** (window-overlap detection across shared weekdays, with a suggested non-conflicting start time) |
| `SleepRepository` | Single-active sleep window |
| `PrayerRepository` | Prayer settings singleton |
| `AppStateRepository` | Active toggle + global shuffle |

Typed exceptions (`ScheduleConflictException`, `PlaylistLimitException`, `DuplicatePlaylistNameException`) bubble up and are translated to localized copy by `core/errors/user_facing_error.dart`.

### File storage

Audio lives on disk, not in the DB: `<app documents>/clips/<uuid>.m4a`.
`services/audio/clip_path_guard.dart` is an allowlist that rejects `..`, non-audio extensions, and anything outside the clips root. `reconcileOrphanClipFiles()` sweeps files with no DB row at startup.

---

## 5. State management (Riverpod)

Legacy declarative Riverpod — `Provider`, `FutureProvider`, `StreamProvider`, `StateNotifierProvider`. `ProviderScope` wraps the app in `main.dart`.

### `providers/repository_providers.dart`
Seven plain `Provider`s exposing the repositories — this is the dependency-injection seam.

### `providers/playback_providers.dart`

| Provider | Type | Purpose |
|---|---|---|
| `playbackCoordinatorProvider` | `Provider` | **The hub.** Constructs the coordinator, wires the notification-refresh callback, calls `initialize()`, disposes on teardown |
| `playbackSnapshotProvider` | `StreamProvider<PlaybackSnapshot>` | The single object the whole UI renders from |
| `nativePlaybackProvider` | `StreamProvider<NativePlaybackSnapshot>` | Native playback state: seeds with a prefs read, then merges the method-channel stream **plus a 1.5 s poll** |
| `clipsProvider` | `FutureProvider` | `keepAlive`; self-invalidates on duration backfill and forces an alarm rebuild |
| `playlistsProvider` / `schedulesProvider` / `activeSleepProvider` / `prayerSettingsProvider` | `FutureProvider` | `keepAlive` list reads |
| `audioPlaybackServiceProvider` / `audioRecordingServiceProvider` / `audioImportServiceProvider` / `prayerServiceProvider` | `Provider` | Service handles |
| `isAppActiveProvider` | `FutureProvider<bool>` | Master toggle state |

### `providers/settings_provider.dart`
`StateNotifier`s backed by SharedPreferences: locale, theme mode, nav labels, default alarm, default interval, plus `firstLaunchProvider`.

### Two providers declared outside `providers/`
- `scheduleEngineProvider` (bottom of `services/scheduler/schedule_engine.dart`) — **starts the engine as a construction side effect**; `app.dart` reads it eagerly in a post-frame callback specifically to trigger that.
- `appRouterProvider` (`core/router/app_router.dart`).

### How the UI subscribes
`MainShell` watches `playbackSnapshotProvider` for mini-player visibility and opens a manual subscription on `coordinator.errors` to show snackbars. `MiniPlayerBar` additionally watches **and** listens to `nativePlaybackProvider` so pause routing stays in sync with native reality.

---

## 6. Audio stack

There are **two completely separate audio engines** in this app, and knowing which is which explains most of the codebase.

| | Engine | Used for |
|---|---|---|
| **A** | `just_audio` (ExoPlayer) via `WhisperAudioHandler` + `audio_service` | Manual in-app playback (user taps a clip), and on iOS the silence keep-alive |
| **B** | Native Kotlin `MediaPlayer` in `WhisperPlaybackService` | **All scheduled playback on Android** |

They must never run at the same time. Most of the historical bugs (auto-pause, missed schedules) were these two fighting over audio focus.

### `WhisperAudioHandler` (`services/audio/whisper_audio_handler.dart`, ~1200 lines)

Extends `BaseAudioHandler with SeekHandler`. Initialised in `main.dart` via `AudioService.init` with an **8-second timeout** and a fallback to an unbound handler so a failed bind can never black-screen the app (`whisperAudioServiceBound` records the outcome; a banner surfaces it).

Notable design decisions:
- Constructed with `handleAudioSessionActivation: false` so the keep-alive loop never grabs audio focus and pauses the user's Spotify.
- **Silence keep-alive:** generates a 10-second silent WAV and loops it at volume `0.001` (not `0` — some OEM audio daemons treat volume 0 as "not playing" and revoke focus). **This is fully disabled on Android** — `enterForeground` and `_startIdleKeepAlive` early-return on `Platform.isAndroid`, because the silence loop was fighting native `MediaPlayer`.
- `suspendSilenceForExternalPlayback()` / `resumeSilenceAfterExternalPlayback()` is the handshake with the native path; suspend also clears the `audio_service` media notification so the only visible transport controls are the ones that actually work.
- `seekForward` / `seekBackward` / `fastForward` / `rewind` are overridden to **no-ops** — Samsung firmware routed long-press-pause through them and sailed past the end of short clips.
- Transport controls are always published in the same order (`prev, play/pause, next, stop`) so compact-bar button positions never shift.

### `PlaybackCoordinator` (`services/playback/playback_coordinator.dart`, ~1900 lines)

The state machine between UI, `just_audio`, and native. It emits `PlaybackSnapshot`, which is what every widget renders.

- **Two serialization gates:** `_serializePlay` (20 s timeout) for anything that starts audio; `_serializePauseResume` (4 s timeout) for pause/resume/dismiss. Both release on timeout so a wedged native call cannot starve future taps.
- **Native ownership routing:** `_nativeOwnsPlayback` checks the local flag *and* the last native snapshot. When true, `pause()` / `resume()` / `stop()` route through the platform channel to `MediaPlayer` instead of `just_audio`, and player-state events are ignored.
- `_onNativePlaybackState` is the single choke point that mirrors native transitions into the UI snapshot, stamps last-fired timestamps, and triggers alarm realignment after each fire.
- Anti-auto-advance sentinels: `_userInitiatedPause`, `_systemDrivenPauseInFlight`, and a `_playbackGeneration` counter so a stale `completed` event from a swapped source is discarded.

---

## 7. Scheduling — the full chain

This is the part the reviewer will care about most. Follow it in order.

### Step 1 — The model

`PlaybackSchedule { playlistId, startTime, endTime?, intervalMinutes, daysMask, enabled, playlistDurationMs }`

`daysMask` is a bitmask: bit 0 = Monday, `127` = every day.

**The interval contract:** the gap is measured from the **end** of the playlist, not the start.

```
effectiveStep = intervalMinutes + playlistDuration
```

A 5-minute playlist on a 10-minute interval starting at 1:00 fires at **1:00, 1:15, 1:30** — not 1:00, 1:10, 1:20. This is computed in millisecond precision (`ScheduleFireHelper.effectiveStep`) with a 60-second placeholder when the playlist duration is not yet known.

### Step 2 — Projection (Dart)

`services/scheduler/native_alarms_bridge.dart` → `applySnapshot()`:

1. **Resolve clips** — for each enabled schedule, load every playable clip path and verify it exists on disk.
2. **Structural fingerprint** — hash `[id, daysMask, start, end, interval, duration, clip paths] + active`. If unchanged and not forced, **do nothing**. This deliberately excludes fire times: an earlier version hashed projected times, so normal drift after each fire triggered a full cancel-and-re-register that killed alarms mid-delivery.
3. **Project fires** — walk forward, strictly-future slots only, capped at **288 per schedule / 400 total** (Android's per-app alarm cap is 500; we leave headroom).

Each fire is a JSON object:
```json
{ "scheduleId": "...", "clipPath": "...", "clipTitle": "...",
  "clipQueueJson": "[...]", "playlistName": "...",
  "fireEpochMs": 1234567890000, "effectiveStepMs": 900000 }
```

### Step 3 — The bridge

`MethodChannel('com.whisperback.alarms')`

| Direction | Method | Purpose |
|---|---|---|
| Dart → Kotlin | `setSnapshot` | Push the fires JSON + active flag; returns registered count |
| Dart → Kotlin | `cancelAll` | Active toggled off |
| Dart → Kotlin | `pauseNative` / `resumeNative` / `stopNative` | Control the scheduled clip |
| Dart → Kotlin | `setVolume` | Push the volume slider value (0.0–1.0) |
| Dart → Kotlin | `getPlaybackState` | Poll current native state from prefs |
| Kotlin → Dart | `onScheduledPlaybackState` | Push every state transition + progress tick |

Two more channels exist: `com.whisperback.keep_alive` (start/stop the keep-alive service) and `com.whisperback.clip_metadata` (`readDurationMs`).

### Step 4 — Alarm registration (Kotlin)

`alarms/WhisperAlarmScheduler.kt` — prefs file `whisperback.alarms`, keys `snapshot_json_v2`, `registered_request_ids`, `registered_fire_epochs`, `is_active`. Constants: `MAX_ALARMS = 400`, `REFILL_THRESHOLD = 8`, `CANCEL_GRACE_MS = 90_000`.

- `syncFromJson` is a **diff-sync**: cancel epochs no longer wanted, keep overlaps, append new ones. It never wipes the table first, and it never cancels anything inside the 90-second grace window (that PendingIntent may already be in OS delivery).
- `registerOne` always prefers `AlarmManager.setAlarmClock(...)`; only a `SecurityException` falls back to `setExactAndAllowWhileIdle`.
- `refillIfNeeded()` runs on **every fire**: when fewer than 8 future fires remain, it extrapolates more using `effectiveStepMs` and appends them — so the chain survives indefinitely even if the Flutter process has been dead for weeks.

### Step 5 — Delivery

`alarms/WhisperAlarmReceiver.kt` — action `com.whisperback.alarms.FIRE`, extras `schedule_id`, `clip_path`, `clip_title`, `playlist_name`, `clip_queue_json`, `slot_epoch_ms`.

1. **Dedup** — prefs `whisperback.alarms.dedup`, key `last_fire_<scheduleId>`, 60-second window (some OEMs re-deliver a queued alarm when leaving Doze).
2. **Lateness gate** — more than 15 minutes late ⇒ skip; 1–15 minutes late ⇒ log and play anyway.
3. `startForegroundService(WhisperPlaybackService)` then `refillIfNeeded()`.

The dedup stamp is written by the *service* after `MediaPlayer.start()` succeeds, not by the receiver — otherwise a failed prepare would block the OS retry.

### Step 6 — Playback

`alarms/WhisperPlaybackService.kt` — `foregroundServiceType="mediaPlayback"`, notification id `0xBA77`, wake lock `WhisperBack:scheduledPlayback` (2 h cap).

- Audio attributes are `USAGE_MEDIA` + `CONTENT_TYPE_MUSIC` so the **media** volume slider applies. (It used to be `USAGE_ALARM`, which routes through the alarm stream — always 100 % — and produced the "plays at full volume" complaint.)
- Plays the whole clip queue sequentially via `setOnCompletionListener`.
- A **500 ms watchdog** restarts `MediaPlayer` if an OEM silently stops it.
- **Audio focus loss ducks to 35 % volume rather than pausing.** Only an explicit user pause sets `userPaused`. This is the anti-auto-pause contract: a scheduled clip stops only on natural completion or a deliberate user action.

### Step 7 — State mirror

Two paths, deliberately redundant:
1. **SharedPreferences** `whisperback.alarms.playback_state` — `state`, `clip_path`, `clip_title`, `playlist_name`, `schedule_id`, `duration_ms`, `position_ms`, `native_playback_active`, `clip_queue_json`, `slot_epoch_ms`, `playback_volume`. Written with `commit()` (synchronous) so Dart cannot read a stale value.
2. **Method channel** via the static `WhisperPlaybackService.stateListener`, wired by `MainActivity` and posted on the main looper.

The prefs path is the fallback for when the Flutter engine is dead; the channel is the fast path.

### Step 8 — Reboot

`alarms/WhisperBootReceiver.kt` handles `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED` and replays the stored snapshot **without booting Flutter**.

### The Dart engine's remaining role

`services/scheduler/schedule_engine.dart` runs a 5-second timer, but on Android `_delegateFiringToNative` is `true` and the firing branch is short-circuited. On Android the engine only refreshes notifications, polls native state, maintains the keep-alive heartbeat, and does failure/backoff bookkeeping. Tests and non-Android hosts still exercise the full Dart firing pipeline.

Last-fired timestamps live in SharedPreferences: `schedule_last_slot_<id>` (the grid time claimed, used for dedup) and `schedule_last_completion_<id>` (actual end, drives interval-from-end).

---

## 8. Native Android layer

| File | Role |
|---|---|
| `MainActivity.kt` | Extends `AudioServiceActivity`. Registers all three method channels, installs the native state listener, edge-to-edge setup. Deliberately does **not** null the state listener in `onDestroy` — OEMs destroy the Activity while audio keeps playing |
| `alarms/WhisperAlarmScheduler.kt` | Owns the AlarmManager table: diff-sync, refill, cancel |
| `alarms/WhisperAlarmReceiver.kt` | Alarm delivery → dedup → lateness gate → start service → refill |
| `alarms/WhisperPlaybackService.kt` | The scheduled-audio player + MediaStyle notification + state mirror |
| `alarms/WhisperBootReceiver.kt` | Re-arms alarms after boot / app update |
| `WhisperKeepAliveService.kt` | Process keep-alive only, **plays no audio**. `foregroundServiceType="specialUse"`, 60-second heartbeat re-asserting `startForeground` + wake lock |
| `ClipMetadataProbe.kt` | `MediaMetadataRetriever` duration read — chosen over `just_audio` because the Dart probe consumed audio focus on Samsung/Vivo and returned null |

### Permissions

`RECORD_AUDIO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `FOREGROUND_SERVICE_SPECIAL_USE`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `RECEIVE_BOOT_COMPLETED`, `RECEIVE_LOCKED_BOOT_COMPLETED`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `READ_MEDIA_AUDIO`, location (prayer), `INTERNET`, `VIBRATE`.

`USE_EXACT_ALARM` is declared on the grounds that alarm-clock scheduling *is* the app's primary purpose. **This is a Play Store policy assertion a reviewer may challenge** — see §13.

### Services declared

Two `mediaPlayback` services coexist (audio_service's and ours). The keep-alive service uses `specialUse` precisely to avoid the Android 14 restriction.

---

## 9. Notifications

Two independent systems, by design.

### `flutter_local_notifications`

| Channel | Importance | Use |
|---|---|---|
| `whisperback_status` | default, silent | The persistent "Active" card (id `1`) |
| `whisperback_now_playing` | default, silent | Now-playing info |
| `whisperback_alarms` | max, sound + vibrate | Schedule reminders (ids `1000–1399`) |
| `whisperback_prayer` | high | Prayer reminders (ids `2000–2069`) |

`syncSchedules` is fingerprint-cached, caps at 50 alarms per schedule / 200 global over a 7-day horizon, and yields between binder calls to avoid ANRs. The Active card is re-posted **twice on every app resume, 500 ms apart**, because Vivo/Xiaomi silently dismiss it during activity transitions.

### Native MediaStyle notification

Channel `whisperback_scheduled_playback` (`IMPORTANCE_LOW`, silent), id `0xBA77`. Pause **or** Resume plus Stop, delivered via `PendingIntent.getService`. No `deleteIntent` — OEMs auto-dismissing the notification was killing playback.

### Coexistence rule
Up to four notifications can be live (Active card, keep-alive, audio_service media card, native playback card). They use distinct IDs and channels. When native playback starts, the `audio_service` card is cleared so the only transport controls visible are the ones that actually control `MediaPlayer`.

---

## 10. Localization

`lib/l10n/app_localizations.dart` is a **2153-line hand-written class** — no ARB files, no `flutter gen-l10n`. Every string is a getter calling a private positional helper `_s(en, ur, ar, nl, fr, vi)`. Six locales: English, Urdu, Arabic, Dutch, French, Vietnamese.

`MaterialApp.router` is keyed on the locale so a language change forces a full rebuild. `RuntimeCopy.bind(...)` runs in the `MaterialApp.builder` so non-widget code (notifications, media metadata) can reach localized strings.

**This is a known deviation from Flutter best practice** — see §13.

---

## 11. iOS status

`ios/` is an essentially untouched Flutter scaffold. `AppDelegate.swift` is the stock registrant and **registers no method channels**.

`Info.plist` declares `NSMicrophoneUsageDescription`, `NSLocationWhenInUseUsageDescription`, and `UIBackgroundModes = [audio]`.

**Not implemented on iOS:**
- All three platform channels — they degrade to silent no-ops via `Platform.isAndroid` guards and `MissingPluginException` handling
- Therefore **no scheduled playback when the app is not running**. No `BGTaskScheduler`, no notification-triggered playback
- No signing or provisioning configuration

The app compiles for iOS (CI proves it) and can play audio in-app, but the core value proposition — whispers that play when the app is closed — does not exist there yet. iOS would need a fundamentally different approach, because iOS has no equivalent of `setAlarmClock`.

---

## 12. Testing and CI

### Tests
46 test files. Three styles:

1. **Pure unit tests** — `schedule_fire_helper_test`, `shuffle_engine_test`, `schedule_conflict_test`, `clip_path_guard_test`
2. **Repository tests against real SQLite** via `sqflite_common_ffi`
3. **Source-level pinning tests** — about 20 files read Dart/Kotlin source off disk and assert on its *contents*:

```dart
final src = _read('lib/providers/playback_providers.dart');
expect(src, contains('Timer.periodic'));
```

**A reviewer must understand this convention.** It is how native/async behaviour that cannot run in the Dart VM is regression-guarded. The side effect is that renaming a Kotlin method — or even editing a comment — can fail a test that never executes the code. Files are named `roundNN_*_test.dart` after the QA round that produced them.

`test/flutter_test_config.dart` is the global harness: it swaps in the FFI SQLite factory and redirects the database path to a per-isolate temp directory so parallel test files don't collide on Windows.

### CI (`.github/workflows/`)

| Workflow | Runner | Steps | Artifacts |
|---|---|---|---|
| `mobile_ci.yml` | ubuntu | `dart format --set-exit-if-changed` → `flutter analyze --no-fatal-infos` → `flutter test` → integration test (non-blocking) → debug APK build | none |
| `build_apk.yml` | ubuntu | analyze → test → `flutter build apk --release --split-per-abi` | `whisperback-release-arm64` (90 d), `whisperback-release-all-abis` (30 d) |
| `build_ios.yml` | macOS | analyze → test → `flutter build ios --release --no-codesign` | `whisperback-ios-unsigned` (compile check only) |

**Formatting is enforced and will fail the build.** Note also that `build_apk.yml` can produce an artifact even when `mobile_ci.yml` fails, so always confirm which commit an APK came from.

---

## 13. Production readiness — known gaps

Be upfront about these; they are the things a good reviewer will find anyway.

### Blockers for a Play Store release

| # | Gap | Detail |
|---|---|---|
| 1 | **Release builds are debug-signed** | `android/app/build.gradle.kts` lines 36–39: `signingConfig = signingConfigs.getByName("debug")` with a `TODO`. Needs a real keystore + `key.properties` (gitignored) or Play App Signing. Every APK shipped to QA so far is debug-signed |
| 2 | **No AAB build** | Play requires Android App Bundle. CI only builds split APKs |
| 3 | **`USE_EXACT_ALARM` policy risk** | Allowed only for apps whose *core* function is alarms/calendar. Our justification is reasonable but should be prepared for review. `SCHEDULE_EXACT_ALARM` with a runtime prompt is the safer fallback |
| 4 | **No crash reporting** | No Crashlytics/Sentry. The global `runZonedGuarded` net swallows errors to `debugPrint` only — in production those failures are invisible |
| 5 | **No release proguard/R8 config** | Not configured; reflection-based paths in the Kotlin services should be verified under minification |

### Quality debt worth discussing

| # | Item | Detail |
|---|---|---|
| 6 | **Hand-written localization** | 2153 lines, no ARB, no tooling. Adding a string means editing one giant file; there is no translator workflow and no way to detect missing translations |
| 7 | **Source-level pinning tests** | Fast to write, brittle to refactor. They assert on comments and identifiers, not behaviour. Worth asking the reviewer whether to keep, convert to integration tests, or supplement with instrumented Android tests |
| 8 | **Two 1000–1900 line files** | `playback_coordinator.dart` (~1900) and `whisper_audio_handler.dart` (~1200) are the app's brains and are past a comfortable review size |
| 9 | **No instrumented Android tests** | The entire native scheduling path — the riskiest code in the app — has zero automated coverage. Everything is verified by manual QA on devices. This is the biggest testing gap |
| 10 | **No DB indices** | Fine at current caps, but unbounded growth of `clips` would hurt |
| 11 | **iOS is not implemented** | See §11 |
| 12 | **Auth is UI-only** | `features/auth/` has sign-in/sign-up screens with no backend. `data/repositories/cloud/` is an empty placeholder |
| 13 | **No analytics / telemetry** | We cannot tell how often a schedule fires late in the field. Adding a lightweight fire-accuracy log would turn QA guesswork into data |

### What is genuinely solid
- The alarm-clock architecture is the correct choice for this problem, and the reasoning is documented in-code
- Error handling is thorough and deliberate — every native call and lifecycle method is guarded
- Offline-first with no network dependency for the core loop
- CI enforces format, analyze, and tests on every push
- Every non-obvious decision carries a comment naming the QA report and the OEM it reproduced on

---

## 14. Conventions a new developer must know

1. **Dart never fires schedules on Android.** If you see the Dart firing pipeline, it is for tests and non-Android hosts only.
2. **The ExoPlayer silence keep-alive is disabled on Android.** `WhisperKeepAliveService` + `AlarmManager` replace it. Re-enabling it will reintroduce auto-pause.
3. **Audio focus loss ducks, it does not pause.** Deliberate. A scheduled clip stops only on completion or explicit user action.
4. **The alarm table is diff-synced, never wiped**, with a 90-second cancel grace window. `cancelAll` at the wrong moment drops the next fire.
5. **`super.stop()` on the audio handler is called from exactly one place** — on some OEMs it kills the Activity.
6. **Comments are load-bearing.** "Round NN —" comments explain which QA report a line fixes, and some are asserted on by tests.
7. **Error handling style:** optimistic UI first, native call second, roll back on failure. Multi-step teardown uses independent `try/catch` per call so one failure never aborts the rest.
8. **Logging:** `debugPrint` guarded by `kDebugMode` in Dart; `android.util.Log` with per-class tags in Kotlin. Nothing ships to a remote sink.

---

## 15. Questions worth asking the reviewer

1. Is `setAlarmClock` + `mediaPlayback` FGS the right model, or is there a newer API we should use on Android 14/15/16?
2. How would you get automated coverage on the native scheduling path — Robolectric, instrumented tests on Firebase Test Lab, or something else?
3. Are the source-level pinning tests defensible, or should they be replaced?
4. What is the correct way to handle OEM battery killers beyond `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and an in-app guide?
5. Is our `USE_EXACT_ALARM` justification likely to survive Play review?
6. Should `PlaybackCoordinator` be decomposed, and along what seam?
7. For iOS, what is the realistic best-case behaviour for scheduled audio, and is it worth building?
8. Would you migrate localization to ARB + `gen-l10n` now, or is the hand-written class acceptable?
9. What telemetry would you add to measure schedule-fire accuracy in the field?

---

## 16. Companion documents in `docs/`

Worth sending alongside this briefing:

| Document | Contents |
|---|---|
| `DEVELOPER_QA_PREP.md` | The stack explained from zero (why Kotlin, why Gradle) plus anticipated questions with answers |
| `ANDROID_COMPATIBILITY.md` | API 24–36 support matrix and per-version behaviour notes |
| `MOBILE_WALKTHROUGH.md` | Feature-by-feature product walkthrough (25 KB) |
| `PRODUCTION_AUDIT.md` | Long-form audit log of every QA round and its root cause |
| `BACKGROUND_RELIABILITY.md` | The three reliability layers and a scenario-by-scenario behaviour matrix |
| `PLAY_STORE_POLICIES.md` | Permission declarations, the `USE_EXACT_ALARM` justification, and the release blocker list |
| `APK_TESTING.md` / `RELEASE_WORKFLOW.md` | How builds are produced and distributed |
| `INSTALLATION.md` / `LOCAL_DEVELOPMENT.md` | Environment setup for a new developer |
| `qa-checklist.md` | Manual QA test cases |
| `playback-states.md` | The playback state machine |

`BACKGROUND_RELIABILITY.md` and `PLAY_STORE_POLICIES.md` were rewritten alongside this briefing to match the current native-alarm architecture. Older docs (`PROJECT_AUDIT.md`, `MOBILE_WALKTHROUGH.md`, `R1.md`) predate several rounds of change — treat them as historical context rather than current spec.

---

## 17. Glossary for the demo

| Term | Meaning |
|---|---|
| **Whisper / clip** | A short recorded or imported audio file |
| **Active toggle** | The master on/off switch; when off, nothing is scheduled or plays |
| **Schedule** | A playlist + start/end time + interval + weekday mask |
| **Fire / slot** | One scheduled playback occurrence at a specific epoch time |
| **Snapshot** | The JSON array of upcoming fires handed from Dart to Kotlin |
| **Structural fingerprint** | A hash of schedule structure used to skip pointless alarm rebuilds |
| **Refill** | Native top-up of the alarm table when fewer than 8 future fires remain |
| **Keep-alive** | A foreground service that keeps the process alive but plays no audio |
| **Mini-player** | The Spotify-style bar above the bottom nav |
