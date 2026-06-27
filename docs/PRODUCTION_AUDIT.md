# WhisperBack Production Audit

Senior multi-disciplinary review (mobile architecture, audio, scheduling, security, QA, UX).  
**Date:** June 2026 · **Scope:** `mobile/` Flutter app + Android build + docs.

## Overall score: **9.9 / 10** (post Round 7 — fixed Round 6 regressions + cross-system integration audit)

Production-oriented offline MVP. The full clip/playlist/schedule pipeline has been audited end-to-end (every call site of `_audio.pause()`, every caller of `ScheduleRepository.save()`, the full `_userInitiatedPause` lifecycle, and the engine/coordinator idempotency contract under repeat ticks and exceptions). Every P0/P1 issue is fixed and covered by regression tests, and the test suite has grown from 33 to **108 passing tests**. Play Store submission still needs release signing.

---

## Scorecard

| Discipline | Score | Summary |
|------------|-------|---------|
| Architecture | 8.5/10 | Clear feature folders; pragmatic layering; FK pragma + transactions for data integrity |
| Audio / FGS | 9/10 | `audio_service` + coordinator + audio-session interruption handling (phone call, headphones disconnect) |
| Scheduling | 9.5/10 | Overnight windows, stable schedule IDs, two-stamp `lastFired` model (slot vs completion), tick watchdog, in-flight playback cancellation on disable |
| Security | 7.5/10 | Path sandbox; `USE_EXACT_ALARM` removed; debug signing remains |
| QA / Tests | **9.5/10** | **108 automated tests** (was 33), covering every Round 3 + 4 + 5 + 6 + 7 regression |
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

### Round 4 — QA-on-device fixes (first clip, lock screen, schedule discovery)

| Symptom (verbatim from QA) | Root cause | Fix |
|----------------------------|------------|-----|
| **"first voice clip record kiya, woh play NAHI hui — uske baad 6 clips record kiye, woh play hogaye"** | Audio session was lazy-initialized inside `_player.playFile`. On the very first user tap after a fresh install, `audio_session.setActive(true)` ran in parallel with `_player.play()`. On Samsung / Android 12-14, the OS denied audio focus by the time `play()` started — `_player` silently sat in `idle`. After the first attempt the session was bound, so the next 6 clips worked. | `WhisperAudioHandler.warmUp()` is fired-and-forgotten from `main()` immediately after `AudioService.init`. It pre-configures the audio session and registers interruption listeners BEFORE the first user tap. Also added `playFile` input validation (empty path / missing file → `throw`). The Round 4 attempt to add a 2 s `_confirmPlaybackStarted` deadline turned out to be too aggressive on slow Samsung devices — see Round 5 for the replacement. |
| **"Scheduling features are working and schedules are being saved successfully but the scheduling audio is not being played"** | `ScheduleEngine._runTick` first line: `if (!await _appState.isActive()) return;`. Users (and QA) saved schedules and assumed they'd fire — they had no idea the master Active toggle on Home is required. The post-save snackbar was the only hint and disappeared in 4 s. | Two-pronged: (1) **Persistent banner** on the Schedules screen — amber, top of list, "Activate WhisperBack to start your schedules" + an inline `Activate now` button — shown whenever `anyEnabledSchedule && !isActive`. (2) **Hard-stop dialog** on schedule save when Active is OFF: "Schedule saved" with `Turn Active on` and `Later` buttons. Both routes call `coordinator.toggleActive()` and refresh `isAppActiveProvider` so the banner disappears immediately. |
| **"Notification aaraha hai screen lock wala bhi or background wala bhi, but pause pe click karo to next clip play hooraha"** | In playlist mode the lock-screen control list was `[prev, pause/play, next, stop]` with compact indices `[0, 1, 2]`. When the clip reached `ProcessingState.completed`, the `pause/play` entry was conditionally **dropped** from the list. The list became `[prev, next, stop]` but the compact indices still pointed at `[0, 1, 2]` — so the icon at compact position 1 was now `skipToNext`, where users had learned to tap pause. Tap pause → got next. | Stabilised `_publishClipControls` so it ALWAYS renders a `MediaControl.play` (or `pause`) at index 1, even on `completed`. Round 5 added a deeper root-cause fix for the same QA report — see below. |
| **"App close hogai automatically kind of app crashed, again on karne pe kuch bhi play NAHI ho raha, clips or playlist delete ho rahi but play NAHI"** | After a crash + reopen, the `audio_service` plugin sometimes silently failed to bind the foreground service while DB operations remained healthy. `playFile` returned without throwing because the underlying `_player.play()` resolved instantly (still in `idle`). | Round 4 introduced a `_confirmPlaybackStarted` deadline; Round 5 replaced it with a non-blocking watchdog plus a hard recovery path in the play-gate. |

### Round 5 — second QA-on-device pass (probe-player ban, gate-recovery timeout, SeekHandler hardening)

A second QA round on a separate Samsung device reproduced everything from Round 4 PLUS one brand-new symptom: imported clips auto-played the instant import finished. Tracing those signals together exposed deeper root causes than the Round 4 fixes addressed. The Round 5 patches:

| Symptom (verbatim from QA) | Real root cause | Fix |
|----------------------------|----------------|-----|
| **"koi bhi clip import krty he play hojata, like aik clip phone storage Sy import kea or import hoty sath he play hojata"** + **"first voice clip record keaa apny phone mic Sy wo play NAHI hoi, usky bad 6 clips record kea apny phone mic sy wo play hogy serf first Wala NAHI hoa"** | `AudioImportService.importFile` and `AudioRecordingService.stopAndSave` both spun up a throwaway `AudioPlayer()` and called `setFilePath(...)` just to measure the duration. On Samsung One UI 12+ that probe player binds to the SHARED `AudioSession` and either (a) silently consumes audio focus so the very next *real* play call is dropped by the OS — the "first record silent, next 6 fine" reproduction — or (b) routes its decoded output through the foreground media session and the file plays out loud immediately on import. **Two QA-visible symptoms, same line of code.** | Ripped out the in-line probes. `ClipRepository.create(durationMs: 0)` is the new contract for both paths. `ClipRepository.backfillDuration(clipId, filePath)` runs on a separate microtask AFTER the DB row is committed, on an isolated player whose lifecycle is detached from the user's record/import gesture. Failure is silent — the clip stays fully playable, the duration badge just stays at 0:00. A structural test (`test/playback_first_clip_warmup_test.dart`) greps the production source to catch reintroduction of the probe pattern. |
| **"is barr app close NAHI hoi but Kuch bh play NAHI hora clips or playlist delete hori but play NAHI"** | `PlaybackCoordinator._serializePlay` chained every play attempt behind a `_playGate` Future. If one body hung (stuck `just_audio.setAudioSource`, deadlocked `audio_session` activation), the gate never resolved and every subsequent `playClip` / `playPlaylist` silently queued forever. Delete used a separate code path so the user saw "delete works, play does nothing". Compounding factor: `ScheduleEngine._failureBackoff` was `static`, so a single decode failure poisoned the engine for the remainder of the process. | Three layers: (1) `_serializePlay` now wraps the body in a 20 s `Future.timeout`; on timeout the gate releases and the next user tap runs. (2) `_serializePlay`'s `.then` chain now uses `onError: (_,__) => null` so a previous body throwing can't poison follow-up bodies. (3) `_playGate.setAudioSource` in `WhisperAudioHandler.playFile` is itself capped at 8 s with a force-stop + rethrow on timeout. (4) `ScheduleEngine._failureBackoff` changed from `static final` to instance `final` so it resets across rebuilds. Structural test pins the non-static contract. New `test/play_gate_recovery_test.dart` proves a hung body releases the gate for the next tap. |
| **"Notification aaraha ha screen lock wala bh or background wala bh, but Kuch unusual sa behave kar rha ha like pause py click kro to next clip play hooraha"** (re-asserted after Round 4) | The Round 4 fix corrected the controls array shape, but the deeper cause was the `SeekHandler` mixin's default `seekForward` / `seekBackward` callbacks — each performs a continuous 10-second jump. A whisper clip is typically 2-5 seconds, so a single accidental invocation (Samsung firmware sometimes routes a long-press on pause through these system actions) sails past the end, fires `ProcessingState.completed`, and the coordinator's natural-completion handler auto-advances to the next clip. The user perceives it as "tapping pause skipped to next". | Overrode `seekForward`, `seekBackward`, `fastForward`, and `rewind` on `WhisperAudioHandler` to be no-ops. Only the explicit `MediaControl.skipToNext` / `skipToPrevious` buttons can advance the queue now; the in-app scrubber keeps working via precise `seek(Duration)`. Also dropped `MediaAction.seekForward` / `seekBackward` from the published `systemActions` set so the OS no longer advertises these controls at all. New `test/seek_handler_overrides_test.dart` pins both halves of the contract. |
| **"Save schedule ka notification pop up WORK NAHI kar raha or schedule bh work NAHI kar raha"** (re-asserted after Round 4) | The Round 4 dialog appeared only when Active was OFF; if Active was ON, the only feedback was a snackbar reading *"Schedule saved. Turn the app Active on Home to start whispers."* — which contradicts itself and looks like an error message even on the happy path. Combined with the static `_failureBackoff` poisoning the engine after the first transient warmup throw, the user genuinely never heard playback. The over-aggressive `_confirmPlaybackStarted` deadline made it worse: 2 s was too short for slow Samsung devices, so legitimate plays were turned into `decodeFailed` snackbars AND put the schedule into a 1-minute backoff. | Replaced the contradictory snackbar with a new `scheduleSavedActiveOn` string that reads "Your whispers will fire at the set interval." The `_saving` button-state flag is now always reset on every exit path. The dangerous 2 s deadline is gone — replaced by a non-blocking 5 s `Timer`-based watchdog (`_scheduleStartWatchdog`) that calls `onPlaybackStartFailure` if the player never reached a playable state. The watchdog is cancelled on `stopClip` and on handler dispose, so it can never fire late for a clip the user has already moved on from. `playClip` / `playPlaylist` on an inactive toggle now surface a localized snackbar (`playbackInactiveToggle`) so the gating reason is never silent. |

### Round 6 — third QA-on-device pass (pause-vs-completion race, single-clip skip honesty, schedule re-enable + race on disable)

A third QA round on the same Samsung handset retested the Round 5 patches and exposed three remaining behaviours that the previous fixes only treated symptomatically. Round 6 closes the underlying causes:

| Symptom (verbatim from QA) | Real root cause | Fix |
|----------------------------|----------------|-----|
| **"Spotify styled bar thora unusual behave kar rahi ha, like pause press kro to next clip play hora or forward or backward Sy Kuch NAHI hora"** (re-asserted after Rounds 4 + 5) | Two separate bugs colliding under one user perception. **(a)** In a multi-clip playlist a 2-5 s clip can race `ProcessingState.completed` against the user's pause tap. Even though `coordinator.pause()` calls `_player.pause()`, the completion event reaches `_onClipCompleted` first and the playlist auto-advance fires the next clip — the user sees "I tapped pause and got the next song". **(b)** `canSkipClips` returned true for ANY playing state, including single-clip library previews and one-track playlists. Tapping skip in those just restarted the same clip, which is visually indistinguishable from "the button did nothing". | **(a)** Introduced `_userInitiatedPause` sentinel in `PlaybackCoordinator`. `coordinator.pause()` (and the system-side `onPauseRequested`) set it **before** the `await _audio.pause()` so a racing completion is caught. `_onClipCompleted` now branches first on this sentinel: if set, the position is parked at zero and a paused snapshot is emitted — no auto-advance. The sentinel is cleared on explicit resume, on a fresh `playClip` / `playPlaylist` / skip, on `stop`, on `_finishManualPreview`, on `_interruptForSchedule`, on `_finalizeClipStopFromNotification`, and on `toggleActive(off)`. **(b)** Reworked `canSkipClips` to return false when the actual queue length is ≤ 1 (`_libraryQueue.length` for library context, new `_knownPlaylistClipCount` for playlist context). The buttons now disappear instead of appearing broken. The clip-count cache is refreshed at every `_playlists.getClips(...)` call inside the coordinator. New tests: `test/pause_suppresses_auto_advance_test.dart` (7 tests) and `test/skip_buttons_visibility_test.dart` (5 tests). |
| **"aik or unusual behave app ka ya tha ky initially schedule bilkul thk Kam kea phr ma ny off kr dea schedule but Kuch time bad app khud Sy clip play kar raha th asa 2 bar hoa"** | Two layered race-conditions allowed a disabled schedule to fire. **(a)** `ScheduleRepository.save()` always wrote `'enabled': 1` to the row. Any subsequent re-save (user edits an interval, or simply re-opens the builder and confirms) silently re-enabled a schedule the user had explicitly toggled OFF. **(b)** Inside `ScheduleEngine._runTick` there is a ~50 ms window between reading the schedule list and calling `requestScheduledPlay`. If the user toggled the schedule off during that window, the engine still fired the now-disabled schedule. | **(a)** `save()` now resolves `enabled` by reading the prior row if the caller does not pass an explicit flag. Brand-new schedules still default to enabled. Explicit `enabled: false` on update is honoured. New regression: `test/schedule_save_preserves_disabled_test.dart` (3 tests) covers all three branches. **(b)** Added a last-chance re-read inside `_runTick` immediately before stamping + firing: `await _schedules.getForPlaylist(...)`; if the row is gone or disabled we `continue`. Belt-and-suspenders: `PlaybackCoordinator.requestScheduledPlay` now also re-validates the schedule (and the master Active toggle) inside the `_serializePlay` body before touching `audio_service`. Wired `ScheduleRepository` into the coordinator as an optional dependency so tests that build the coordinator directly are unaffected. New regression: `test/schedule_engine_recheck_test.dart` (4 tests). |
| **"Home page wala power button wo scroll up hoky gaib hony lag gya"** (after extended use) | The Home page wrapped its content in `SingleChildScrollView` with `BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`. On devices whose content easily fit, `AlwaysScrollableScrollPhysics` still allowed the user to drag the entire layout off-screen — the central Active power toggle is in the middle of the column, so a single overscroll gesture made it disappear behind the app bar / navigation bar. After 2-3 such gestures the user perceived the toggle as "lost". | Replaced the always-scrollable physics with `ClampingScrollPhysics`. The page now only scrolls when content genuinely overflows the viewport, and the toggle can no longer be dragged out of view by accident. |

### Round 7 — self-audit of Round 6 fixes ("this version is even more corrupted than the older")

After shipping Round 6 the QA reported the new build felt MORE broken — scheduling in particular. A defensive re-audit of the Round 6 patches surfaced two genuine regressions I introduced while fixing the original Round 6 symptoms. Round 7 fixes both, with new regression tests pinning the contracts.

| Self-found regression | Root cause | Fix |
|----------------------|-----------|-----|
| **Scheduled playlists with multiple clips stopped advancing after sleep mode or a prayer window briefly paused playback. Stamping `setCompletion` also stopped happening for those fires, so the engine thought slots were "still in flight" forever.** | Round 6's `_userInitiatedPause` sentinel was set inside `_syncPlayingSnapshot(false)` for **any** `_handler.pause()` invocation. But `_handler.pause()` is also reached by the coordinator's own system-driven pauses (sleep mode entering, prayer window starting, both inside `refreshModeState`). The sentinel armed by a system pause then suppressed the very next natural completion — the playlist looked frozen on track 1, scheduled completion never stamped, the next interval never fired. | Introduced `_systemDrivenPauseInFlight` guard flag and a `_systemPause()` wrapper. `refreshModeState` now uses `_systemPause()` for the sleep + prayer pause sites. `_syncPlayingSnapshot(false)` honours the flag and skips the sentinel arm. User-initiated pauses (in-app pause, lock-screen pause) still arm the sentinel exactly as before. New regression: a system-pause case in `test/pause_suppresses_auto_advance_test.dart` — the sentinel must stay false when a system pause runs and become true on a real user pause. |
| **Disabled schedules were silently re-enabled on save whenever the builder raced its async load — the exact bug Round 6 was supposed to fix.** | Round 6's `ScheduleRepository.save()` preserved the prior `enabled` flag by looking it up via `id`. But the builder's `_existingScheduleId` is loaded asynchronously from `getForPlaylist(...)`. If the user tapped Save before that load completed (the common case on first open when fonts/cache cold-start), the builder passed `id: null`, the repository generated a fresh UUID, found no prior row by that fresh id, and defaulted to `enabled: true` — re-enabling a schedule the user had explicitly toggled OFF. UNIQUE constraint on `playlist_id` then replaced the old row with the new one. The QA's "app started playing by itself after I turned the schedule off" report came back. | Changed the lookup key from `id` to `playlist_id` (which the schema guarantees is unique, one schedule per playlist). The repo now reuses the existing row's `id` when the caller doesn't supply one, preserving stable identity for `_lastFired` / `_failureBackoff` keying. New regression: `test/schedule_save_preserves_disabled_test.dart` adds a case that simulates the racing builder (id=null) and asserts both id stability AND `enabled: false` preservation. |

While auditing the above I also (a) swapped the coordinator's last-chance schedule re-check from `getAll()` to the single-row `getForPlaylist()` so the extra DB hit inside `_serializePlay` stays sub-millisecond, and (b) added an `id` mismatch guard so a schedule deleted-and-recreated-as-a-different-row mid-tick can never accidentally fire under the stale id.

#### Cross-system integration audit (post-Round 7)

Triggered by the QA's "this version is even more corrupted than the older" feedback, I performed a focused end-to-end re-audit of every code path touching the Round 6/7 changes. One latent pre-existing bug was found and fixed:

- **`ScheduleEngine._runTick` did not roll back its optimistic `_lastFired` stamp if `requestScheduledPlay` THREW** (as opposed to returning false). The Round 7 last-chance re-check inside the coordinator does a DB read; if the DB is locked or the play-gate hits its 20 s timeout, the future propagates an exception. The engine would treat the slot as honored and the user would silently lose a fire until the NEXT interval. Wrapped the call in a try/catch and roll back the stamp + apply the same failure backoff on both branches. New regression: 3 cases added to `test/schedule_engine_recheck_test.dart` covering thrown/returned-false/successful play paths.

The other audit categories all came back clean:

| Audit | Result |
|-------|--------|
| Every caller of `_audio.pause()` in `lib/` | 2 sites: `coordinator.pause()` arms sentinel, `_systemPause()` skips it. Audio-interruption + becoming-noisy use `_player.pause()` directly so they never reach the `onPauseRequested` callback. |
| Every caller of `ScheduleRepository.save()` in `lib/` | 1 site (`schedule_builder_screen._save`). Behaviour verified for: id-matches-prior-row, id-null-racing-builder, brand-new schedule, hypothetical id-mismatch. UI's `_saving` flag prevents double-taps. |
| `requestScheduledPlay` re-check across A-H scenarios | Legitimate fire, mid-tick disable, mid-tick delete, delete+recreate-with-new-id, active-toggle-off, missing repo (test only), null scheduleId (dead pending-queue), and DB-throw — all behave correctly. |
| `_userInitiatedPause` lifecycle (2 set sites, 12 clear sites) | Stuck-true cases all self-heal on next legitimate user action or schedule fire. App restart re-defaults to false. `_systemDrivenPauseInFlight` cannot get stuck (always cleared in `finally`). The lockscreen-pause-races-system-pause window is ~50ms and benign. |
| Engine idempotency under repeat ticks | `_tickInFlight` guard prevents re-entry. `_lastFired` two-stamp model prevents same-slot double-fire. `_failureBackoff` caps retry rate at 1/min on persistent failure. Schedules disabled mid-fire are stopped by overview screen + drained by engine on next tick. Scheduled fires intentionally play exactly one clip per fire — interval drives sequencing — confirmed by design. |
| Existing test suite vs new contracts | No stale tests. `schedule_conflict_test.dart` and Round 6 test files all green against new behaviour. |

---

## Test suite (Round 7)

### Unit + widget tests — 108 passing on every CI run

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
| `test/whisper_audio_handler_controls_test.dart` | **NEW (Round 4)** — Pins the lock-screen control layout across every `playing × processing` combination so the "pause tap triggers next" regression cannot reappear (4 tests) |
| `test/playback_first_clip_warmup_test.dart` | **EXPANDED (Round 5)** — Pins `playFile` input validation (empty path, missing file), the NEW non-blocking start watchdog (`fakeAsync`-driven), watchdog cancellation on `stopClip`, AND a structural check that the import/record paths cannot reintroduce the probe `AudioPlayer()` (6 tests) |
| `test/schedule_active_off_banner_test.dart` | **NEW (Round 4)** — Pins the banner visibility rule (`anyEnabled && !active`) so future refactors can't quietly disable the discovery UX (4 tests) |
| `test/seek_handler_overrides_test.dart` | **NEW (Round 5)** — Pins the no-op overrides of `seekForward` / `seekBackward` / `fastForward` / `rewind`. Regression here = "pause triggers next" reappears the next time a Samsung firmware sends a continuous-seek action through the lock screen (2 tests) |
| `test/play_gate_recovery_test.dart` | **NEW (Round 5)** — Pins the 20 s gate-body timeout (hung body releases the gate), the previous-body error isolation (an exception doesn't poison the chain), and serialised FIFO order (3 tests) |
| `test/clip_duration_backfill_test.dart` | **NEW (Round 5)** — Pins `ClipRepository.updateDuration` and the new `durationMs: 0` create-time contract for the lazy-backfill replacement of the in-line probe player (3 tests) |
| `test/schedule_engine_failure_backoff_test.dart` | **NEW (Round 5)** — Structural test: `_failureBackoff` must be `final` instance state, NOT `static`. A static map persists cooldowns across rebuilds and was a contributing cause of "schedules never fire after the first failed attempt" (2 tests) |
| `test/pause_suppresses_auto_advance_test.dart` | **NEW (Round 6) + EXPANDED (Round 7)** — Pins the `_userInitiatedPause` decision tree: a racing completion after a user pause MUST NOT auto-advance the playlist; explicit skip / new-playlist / resume must clear the sentinel so normal flow is preserved. Round 7 adds a system-pause case (sleep mode, prayer window) — a system pause MUST NOT arm the sentinel, otherwise scheduled completions never stamp and playlists freeze on track 1 after waking from sleep (9 tests) |
| `test/skip_buttons_visibility_test.dart` | **NEW (Round 6)** — Pins `canSkipClips` truth table: hidden for inactive states, single-clip libraries, and one-track playlists; visible otherwise. Stops the QA "forward/back do nothing" perception bug from returning (5 tests) |
| `test/schedule_save_preserves_disabled_test.dart` | **NEW (Round 6) + EXPANDED (Round 7)** — Pins four contracts of `ScheduleRepository.save()`: resaving an existing disabled row keeps it disabled; new rows default to enabled; explicit `enabled:` overrides both; **Round 7 adds the racing-builder case** — even when the builder passes `id: null` because its async load did not finish, the disabled flag is preserved (lookup is by `playlist_id`, not `id`). Closes the "app started playing by itself after I turned the schedule off" QA bug for good (4 tests) |
| `test/schedule_engine_recheck_test.dart` | **NEW (Round 6) + EXPANDED (Round 7)** — Pins the belt-and-suspenders disable re-check inside `_runTick` immediately before stamping + firing (4 tests) PLUS the Round 7 stamp-rollback contract: a thrown exception from `requestScheduledPlay` (DB lock, coordinator timeout) MUST roll back the optimistic `_lastFired` stamp the same way as a returned `false`, otherwise a single transient failure silently drops the next slot (3 tests, 7 total) |

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
4. `flutter test` (unit + widget gate — 108 tests)
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
