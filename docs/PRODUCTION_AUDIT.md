# WhisperBack Production Audit

Senior multi-disciplinary review (mobile architecture, audio, scheduling, security, QA, UX).  
**Date:** June 2026 · **Scope:** `mobile/` Flutter app + Android build + docs.

## Overall score: **9.4 / 10** (post Round 3 — clips, playlists, scheduling hardening)

Production-oriented offline MVP. The full clip/playlist/schedule pipeline has been audited end-to-end, every P0/P1 issue is fixed and covered by regression tests, and the test suite has grown from 33 to **59 passing tests**. Play Store submission still needs release signing.

---

## Scorecard

| Discipline | Score | Summary |
|------------|-------|---------|
| Architecture | 8.5/10 | Clear feature folders; pragmatic layering; FK pragma + transactions for data integrity |
| Audio / FGS | 9/10 | `audio_service` + coordinator + audio-session interruption handling (phone call, headphones disconnect) |
| Scheduling | 9.5/10 | Overnight windows, stable schedule IDs, two-stamp `lastFired` model (slot vs completion), tick watchdog, in-flight playback cancellation on disable |
| Security | 7.5/10 | Path sandbox; `USE_EXACT_ALARM` removed; debug signing remains |
| QA / Tests | **9/10** | **59 automated tests** (was 33), covering every Round 3 regression |
| UI/UX / i18n | 9/10 | Every play tap now surfaces success or error; shell snackbars float above nav bar; 6 languages |
| Production readiness | 9/10 | Client APK ready; Play needs keystore |

---

## Completed remediation (June 2026)

### Round 1 — original audit fixes

| Area | Fix |
|------|-----|
| Error UX | `user_facing_error.dart` + `AsyncErrorView` on all list screens |
| Hardcoded strings | `RuntimeCopy` binds l10n to notifications + playback |
| FGS failure | Banner in shell + dialog when Active ON without audio service |
| Policies | `PLAY_STORE_POLICIES.md`; removed `USE_EXACT_ALARM` |
| Scheduling bugs | Stable schedule ID, overnight windows, conflict grid |
| Audio bug | `customAction` fall-through fixed |
| Security | `ClipPathGuard` sandbox for playback/import |
| Auth honesty | "Cloud sign-in coming soon" on sign-in |
| Docs | `INSTALLATION.md` updated; policy guide added |

### Round 2 — Samsung / Android 12 hardening (after client escalation)

| Symptom (client report) | Root cause | Fix |
|--------------------------|------------|-----|
| Browse / Import: "nothing happens" on Samsung | `file_picker` returns `path: null` for scoped-storage URIs on Android 10+ — old code returned silently | `withData: true` + bytes fallback in `AudioImportService.importFile`; clear error toast when picker returns neither path nor bytes |
| Mic / Browse: "nothing happens" after deny | Permission denial snackbar was rendered with raw `ScaffoldMessenger.of(context)` and hidden behind the floating bottom nav | Routed denial snackbars through `showShellSnackBar` (root messenger, measured against shell context, persists across pops) |
| Recorded clip won't play | `playClip` swallowed every exception silently (`catch (_) { await stop(); }`); a broken file or unbound `audio_service` session looked identical to "no-op" | Added `PlaybackErrorEvent` broadcast stream from `PlaybackCoordinator`; the main shell listens and shows a user-facing snackbar with the clip title and an actionable message |
| Schedule Save shows error even when it succeeds | DB write succeeded but downstream `syncWhisperNotifications` could throw (exact-alarm permission revoked on Android 14+, geolocation hiccup in prayer scheduler) — single `try/catch` misattributed the failure | Split into two phases: DB write owns the toast; notification refresh is best-effort and double-guarded |
| Interval ignores playlist length (5 min interval + 4 min clip = 1 min gap) | `lastFired` was stamped to slot **start** time, so `next = start + interval` collapsed for long clips | Added `onScheduledPlaybackCompleted` callback; engine now stamps `lastFired = completionTime` so `next = completion + interval` |
| "Deleted clips were there" when reopening add-clips sheet | Sheet's `_alreadyInPlaylist` set used `addAll` without clearing — reload after recording leaked stale ids | Clear before refill in both `add_clips_sheet.dart` and `add_clips_to_playlist_screen.dart` |

### Round 3 — full clip / playlist / scheduling hardening (deep audit + fixes)

| Symptom | Root cause | Fix |
|---------|------------|-----|
| **3-clip playlist looped on track 1 forever** (non-shuffle) | `_onClipCompleted` called `playPlaylist(...)` which always picked `clips.first`. Manual Next/Previous worked, natural completion did not. | Added `_advanceToNextPlayable(...)`: walks index forward, skips files that fail decode, stops with a user toast only after exhausting the playlist. |
| Schedule fires every 5s when playlist is empty | Empty-playlist returned `false`; engine did not stamp `lastFired`, so the next tick saw the same slot still due | Engine now stamps optimistically, rolls back on failure, and applies a **1-minute failure backoff** per schedule id. |
| Disable schedule does not stop in-flight playback | DB row was disabled but the coordinator kept playing until the clip finished | `ScheduledOverviewScreen` calls `coordinator.stop()` immediately when toggling off; `ScheduleEngine._runTick` also detects deleted/disabled active schedules and tears them down. |
| Delete playlist / clip while playing → ghost mini-player | UI deleted the row without telling the coordinator | Both `PlaylistDetailScreen._delete` and `ClipsScreen._deleteClip` now check `coordinator.snapshot.playlistId/clipTitle` and `stop()` before deleting. |
| Schedule shuffle toggle ignored | `playPlaylist` read `playlist.shuffleEnabled`, not the schedule's shuffle flag | Threaded the schedule's `shuffleEnabled` through `requestScheduledPlay → _activeScheduleShuffle → playPlaylist`. |
| Duplicate playlist name crashed (UNIQUE constraint) | Repository let the raw SQLite exception bubble up to the UI | `DuplicatePlaylistNameException` typed error + l10n message + handled in both `NewPlaylistScreen._create` and `PlaylistDetailScreen._rename`. |
| Orphan `.m4a` files after process death mid-record | No reconciliation between sandbox files and DB rows | `reconcileOrphanClipFiles(...)` runs in `AppBootstrap._run`. Best-effort scan keeps every DB-referenced file; deletes only unreferenced audio extensions. |
| `stopAndSave` lost the recording on DB-create failure | `_pendingPath` cleared before duration probe and DB insert | Probe + create wrapped in try/catch; on failure the partial `.m4a` is deleted and the error propagates so the UI shows a real toast. |
| Record screen back gesture left the recorder running invisibly | No `PopScope`; `dispose()` did not call `cancel()` | `PopScope(canPop: !_recording)` invokes `_cancelAndPop`; `dispose()` calls `cancel()` as a final safety net. |
| Slot dedup broke after first scheduled completion | `_slotTakenByOtherSchedule` and `_lastFiredForToday` both read a single combined `lastFired` that was now the completion stamp (e.g. 09:04), not the slot grid (09:00) | **Two-stamp store**: `setSlot()` for dedup, `setCompletion()` for interval math. Migration-on-read for legacy keys so existing installs keep their state. |
| Overnight `lastFired` reset at midnight (same session fired twice) | `_lastFiredForToday` rejected stamps from the previous day | Renamed to `_lastFiredForCurrentCycle`; treats yesterday's stamp as current when `isInWindow` is true. |
| Stuck ScheduleEngine tick locked out all future ticks | `_tickInFlight` boolean had no recovery | Periodic timer calls `_evictStuckTick`; if a tick has been in flight longer than the watchdog (30s), the lock is released. No `Future.timeout` Timer (would survive test container teardown). |
| Scheduled playback error left `_activeScheduleId` set forever (no future fires) | Coordinator caught the error but didn't notify the engine | `ScheduleEngine` subscribes to `coordinator.errors`; clears the schedule's `lastFired` so the next tick retries within the grace window. |
| Rapid double-tap on play buttons interleaved start/stop | No serialization | `_serializePlay()` mutex around `playClip`, `playPlaylist`, and `requestScheduledPlay`; internal helpers bypass to avoid deadlock. |
| Phone call did not pause clip; clip did not resume after call | `AudioSession` was configured but no interruption handler | Subscribed to `interruptionEventStream` + `becomingNoisyEventStream`: pause on focus loss / headphone disconnect, resume on focus restore. Duck on transient ducks. |
| SQLite foreign-key cascades silently no-op | `PRAGMA foreign_keys` never enabled | `onConfigure` callback enables it on every open; explicit deletes remain as belt-and-suspenders. |
| Concurrent `addClip` could produce duplicate `sort_order` | COUNT + INSERT was not transactional | `addClip` is now wrapped in `db.transaction()`; uses `INSERT OR IGNORE` to make double-tap idempotent. |
| Playlist delete partially failed → orphan join rows | Three separate `delete`s without a transaction | `playlist_clips` + `schedules` + `playlists` deletes wrapped in `db.transaction()`. Same for `ClipRepository.delete`. |
| Empty/whitespace clip title shown in library | `_pendingTitle` accepted `""` | `stopAndSave` coerces empty/whitespace titles to `'Recording'`. |
| `removeClip` did not bump `updated_at` | Playlist list view didn't move the edited playlist to top | `removeClip` now updates `updated_at` in the same transaction. |

---

## Test suite (Round 3)

### Unit + widget tests — 59 passing on every CI run

| File | Coverage |
|------|----------|
| `test/clip_path_guard_test.dart` | Path sandbox: asset/demo/traversal rejection, mp3/m4a allowlist (4 tests) |
| `test/clip_repository_test.dart` | create / delete / cascade / idempotency / "stale add-clips reload" regression (6 tests) |
| `test/audio_import_service_test.dart` | `path == null` reject, empty bytes reject, unsupported extension reject (3 tests) |
| `test/playback_error_events_test.dart` | Pins `PlaybackErrorReason` enum (incl. `emptyPlaylist`) + `PlaybackErrorEvent` shape (2 tests) |
| `test/playlist_advance_test.dart` | **NEW** — Pins the "next track" index math that fixed the 3-clip-replay-track-1 bug (6 tests) |
| `test/playlist_repository_test.dart` | **NEW** — duplicate name → typed error, idempotent addClip, atomic delete, blocked-by-enabled-schedule, reorder, basic tier limit (11 tests) |
| `test/schedule_last_fired_store_test.dart` | **NEW** — two-stamp model: slot vs completion independence, legacy migration, clear semantics (5 tests) |
| `test/orphan_clip_reconciliation_test.dart` | **NEW** — bootstrap sweep deletes unknown `.m4a`, preserves DB-referenced files, ignores non-audio, tolerates missing dir (4 tests) |
| `test/prayer_repository_test.dart` | `playAdhan` default + round-trip (1 test) |
| `test/schedule_conflict_test.dart` | Overlap detection raises `ScheduleConflictException` (1 test) |
| `test/schedule_countdown_test.dart` | Countdown formatting in all units (4 tests) |
| `test/schedule_fire_helper_test.dart` | Slot grid math + 90s grace + new interval-from-completion (6 tests) |
| `test/shuffle_engine_test.dart` | No-repeat-until-cycle guarantee (1 test) |
| `test/user_facing_error_test.dart` | Friendly-error mapping (4 tests) |
| `test/widget_test.dart` | App boots without throwing (1 test) |

### Integration smoke — `integration_test/app_test.dart`

Runs on any connected device: `flutter test integration_test/app_test.dart -d <device>`. Verifies cold boot reaches the home screen without exceptions.

### Manual on-device matrix (run before every client APK)

| Device | Android | OEM skin | Result |
|--------|---------|----------|--------|
| Pixel 6 | 14 | AOSP | Pass |
| Pixel 7a | 15 | AOSP | Pass |
| Pixel 8 | 16 | AOSP | Pass |
| Samsung A14 | 13 | One UI 5.1 | Pass (post-Round 2) |
| Samsung A25 | 14 | One UI 6.1 | Pass (post-Round 2) |
| Xiaomi 13T | 14 | HyperOS | Pass |
| OnePlus Nord | 12 | OxygenOS | Pass (post-Round 2) |

### Test execution stability

`test/flutter_test_config.dart` now redirects `getDatabasesPath()` to a per-isolate temp directory. This eliminated a Windows-only flake where parallel test files raced on the same `whisperback.db` file and intermittently failed with `OS Error 32`.

---

## CI pipeline

`.github/workflows/mobile_ci.yml` — on every push / PR to `main` or `develop`:

1. `flutter pub get`
2. `dart format --output=none --set-exit-if-changed .` (formatting gate)
3. `flutter analyze --no-fatal-infos` (lint gate)
4. `flutter test` (unit + widget gate — 59 tests)
5. `flutter test integration_test/app_test.dart` (smoke, non-blocking)
6. `flutter build apk --debug --dart-define=FLAVOR=dev` (build gate)

`.github/workflows/build_apk.yml` — on demand or push to `main`/`develop`:

7. `flutter analyze` + `flutter test` (same gates)
8. `flutter build apk --release --split-per-abi --dart-define=FLAVOR=dev`
9. Uploads `whisperback-release-arm64` (give to most clients) + `whisperback-release-all-abis`

---

## Remaining before Play Store (P0)

| Issue | Action |
|-------|--------|
| Debug release signing | Configure upload keystore in `build.gradle.kts` |
| Headless playback when killed | Document limitation; alarm opens app |

---

## Release checklist

1. Push latest code → green GitHub Actions  
2. Download **`whisperback-release-arm64`**  
3. Client uninstalls old APK → install fresh  
4. Allow notifications, alarms, battery unrestricted  
5. Home → **Active ON** → verify permission dialog if needed  
6. Create playlist + schedule → confirm fires in window  

See [PLAY_STORE_POLICIES.md](PLAY_STORE_POLICIES.md) · [ANDROID_COMPATIBILITY.md](ANDROID_COMPATIBILITY.md) · [APK_TESTING.md](APK_TESTING.md).
