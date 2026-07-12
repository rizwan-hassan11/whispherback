import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../domain/entities/playback_schedule.dart';
import '../../domain/playback/playback_state.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../notifications/notification_sync.dart';
import '../playback/playback_coordinator.dart';
import 'schedule_engine_binding.dart';
import 'schedule_fire_helper.dart';
import 'schedule_last_fired_store.dart';

typedef ScheduleNotificationSync = Future<void> Function();

/// Fires scheduled clip playback at interval boundaries.
class ScheduleEngine {
  ScheduleEngine({
    required AppStateRepository appStateRepository,
    required ScheduleRepository scheduleRepository,
    required PlaybackCoordinator coordinator,
    required ScheduleLastFiredStore lastFiredStore,
    this.onNotificationsSync,
    bool? delegateFiringToNative,
  })  : _appState = appStateRepository,
        _schedules = scheduleRepository,
        _coordinator = coordinator,
        _lastFired = lastFiredStore,
        // Round 23 — on Android the native `WhisperAlarmScheduler` +
        // `WhisperPlaybackService` pair owns actual audio firing.
        // Letting the Dart engine ALSO call `requestScheduledPlay`
        // for the same slot creates two competing audio streams and
        // a race that trashes the alarm-table rebuild mid-fire (the
        // QA report "later schedules delayed / stopped working"
        // reproduced on every device that let the two paths race).
        //
        // The Dart engine still runs on Android — it drives
        // notification refresh, keep-alive heartbeats, and the
        // failure/backoff bookkeeping — but the firing branch of
        // `_runTick` is short-circuited so ONLY native alarms play
        // scheduled clips.
        //
        // Tests and non-Android hosts continue to fire from Dart
        // (they cover the full firing pipeline; the platform-guard
        // wouldn't be reachable there anyway).
        _delegateFiringToNative =
            delegateFiringToNative ?? (!kIsWeb && Platform.isAndroid) {
    // Whenever a scheduled clip finishes naturally, stamp `completion` with the
    // actual completion timestamp so the next slot is computed as
    // `completionTime + intervalMinutes`. Without this, the next fire would
    // be `slotStart + interval`, which collapses to ~1 minute of silence for
    // a 4-minute playlist on a 5-minute interval.
    _coordinator.onScheduledPlaybackCompleted = _onScheduledCompleted;
    // Listen for playback errors during scheduled runs so we can clear the
    // active schedule lock and let the next tick retry instead of being stuck
    // with `_activeScheduleId` set but no completion ever arriving.
    _errorSubscription = _coordinator.errors.listen(_onPlaybackError);
  }

  final AppStateRepository _appState;
  final ScheduleRepository _schedules;
  final PlaybackCoordinator _coordinator;
  final ScheduleLastFiredStore _lastFired;
  final ScheduleNotificationSync? onNotificationsSync;
  final bool _delegateFiringToNative;
  Timer? _timer;
  StreamSubscription<PlaybackErrorEvent>? _errorSubscription;

  bool _started = false;
  bool _tickInFlight = false;

  /// Whether this engine defers actual scheduled-clip playback to the
  /// native alarm scheduler (Android). When true, the tick body still
  /// runs — refreshing notifications, evicting stuck ticks, honoring
  /// active schedule bookkeeping — but never calls
  /// `coordinator.requestScheduledPlay`. Native alarms are the
  /// single source of truth. Exposed for tests.
  @visibleForTesting
  bool get delegateFiringToNative => _delegateFiringToNative;

  /// Watchdog: if a tick body hangs longer than this, force `_tickInFlight`
  /// back to false so we don't lock all future scheduling. 30s is generous
  /// enough that real DB I/O + notification sync won't trip it.
  static const _tickWatchdog = Duration(seconds: 30);

  /// Cooldown after an empty-playlist or unplayable scheduled fire so we
  /// don't hammer the engine every 5s while the user is fixing the
  /// playlist. NOT `static` — must reset every time the engine is
  /// re-created (e.g. fresh app launch, dependency injection rebuild).
  /// A static map persisted spurious cooldowns from previous lifecycles
  /// and was a contributing factor to the QA report that "schedules never
  /// fire" after the app had thrown a transient warmup error early in
  /// the session.
  final Map<String, DateTime> _failureBackoff = {};
  // Per-schedule consecutive-failure count. Drives an exponential
  // backoff so a single transient failure (audio_service still binding
  // on cold start) only delays the schedule by 5 s, but a genuinely
  // broken playlist (empty / unplayable) doesn't keep getting retried
  // every 5 s in perpetuity.
  final Map<String, int> _failureStreak = {};
  static const _baseBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(minutes: 2);

  Duration _backoffFor(int streak) {
    // 5s → 10s → 20s → 40s → 80s → 120s (capped)
    final secs = _baseBackoff.inSeconds * (1 << (streak - 1).clamp(0, 5));
    final clamped = secs > _maxBackoff.inSeconds ? _maxBackoff.inSeconds : secs;
    return Duration(seconds: clamped);
  }

  void start() {
    if (_started) return;
    _timer?.cancel();
    _started = true;
    // Round 20: on every fresh start (cold launch, isolate revival,
    // engine rebuild) the engine treats the first ~30 seconds as the
    // "boot window". During the boot window any past slot inside the
    // lateness grace window is SKIPPED unless the caller passes
    // `force: true` (alarm-tap or explicit fire). Without this guard
    // the user's exact QA — "I opened the app and a clip played 1
    // minute later even though 7 minutes were left for the next
    // whisper, must have been an old missed slot" — reproduced every
    // time the engine restarted near a slot boundary. The grace
    // window is still honored for genuine recovery from a 30-60s
    // OS pause WHILE the engine is running, just not for ticks
    // immediately after start.
    _bootedAt = DateTime.now();
    unawaited(fireNow());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _evictStuckTick();
      unawaited(fireNow());
    });
  }

  /// Wall-clock at which `start()` last ran. Used by [_runTick] to
  /// suppress lateness-grace firing during the first ~30 s after a
  /// cold/warm engine start. Null until `start()` runs.
  DateTime? _bootedAt;

  /// How long after [start] we treat as "boot window" — past slots in
  /// this window are NOT fired automatically, only on explicit
  /// `force: true`. Engineering tradeoff between recovering from a
  /// genuine OS-paused tick (good for grace) vs. surprising the user
  /// with an old slot the moment they open the app (bad).
  static const _bootWindow = Duration(seconds: 30);

  bool get _inBootWindow {
    final boot = _bootedAt;
    if (boot == null) return false;
    return DateTime.now().difference(boot) < _bootWindow;
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _errorSubscription?.cancel();
    _errorSubscription = null;
  }

  bool get isRunning => _started;

  /// Runs one scheduling pass — safe to call from timers, lifecycle, or alarms.
  ///
  /// When [force] is true, the lateness cap is bypassed so a slot that
  /// the OS missed (process killed in Doze, app swiped away) still fires
  /// when the user taps the alarm notification. Use force only for
  /// user-initiated wake-ups; periodic ticks must respect lateness so
  /// they don't surprise the user with old slots.
  Future<void> fireNow({bool force = false}) async {
    if (!_started || _tickInFlight) return;
    _tickInFlight = true;
    try {
      // Run the tick body; if it never resolves (DB hang, plugin deadlock),
      // a sibling cancellation polls every periodic tick check that
      // `_tickInFlight` hasn't gone stale via `_stuckSince`. Avoids relying
      // on a `Future.timeout` Timer that would otherwise survive a widget
      // test's container dispose and trigger the "pending timers" assert.
      _stuckSince = DateTime.now();
      await _runTick(force: force);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ScheduleEngine: tick failed: $e\n$st');
      }
    } finally {
      _tickInFlight = false;
      _stuckSince = null;
    }
  }

  DateTime? _stuckSince;

  /// Called by the periodic timer to clear `_tickInFlight` if a previous tick
  /// has been running longer than the watchdog window. Lets the engine
  /// recover from a single hung tick without spawning its own Timer.
  void _evictStuckTick() {
    final since = _stuckSince;
    if (since == null) return;
    if (DateTime.now().difference(since) <= _tickWatchdog) return;
    if (kDebugMode) {
      debugPrint(
        'ScheduleEngine: previous tick stuck > $_tickWatchdog — releasing lock.',
      );
    }
    _tickInFlight = false;
    _stuckSince = null;
  }

  /// Tracks the last time we proactively re-synced the persistent
  /// notification. Without a regular re-sync, the displayed "next at"
  /// time becomes stale between fires (which can be 10s of minutes
  /// apart), so the user sees a different value in the notification
  /// than on the schedule page. The page re-renders its countdown
  /// every 30s via its own Timer; we mirror that cadence here so
  /// the two surfaces stay aligned.
  DateTime? _lastNotificationSync;
  // Round 15: dropped from 30s to 5s (matches the engine tick). The
  // notification line "Next at 1:18" was staying stale for up to 30
  // seconds after the slot actually fired, which the QA report called
  // out verbatim ("notification shows 1:18 when current time is
  // 1:20"). At 5s the user-perceived refresh feels instant, and
  // `syncSchedules` now early-returns by fingerprint when nothing
  // changed so the steady-state cost is just a single
  // `_plugin.show(_ongoingId, …)` text refresh.
  static const _notificationSyncCadence = Duration(seconds: 5);

  Future<void> _runTick({bool force = false}) async {
    if (!await _appState.isActive()) {
      // Even when not Active, periodically poke the notification sync
      // so a recent toggle-OFF cancels the ongoing card promptly.
      await _maybeSyncNotifications(force: _inBootWindow);
      return;
    }

    // Round 20: ALWAYS force a notification refresh on the very first
    // tick after `start()`. Without this, the persistent notification
    // can show stale data from the previous process's last sync (the
    // user's QA "it's 10:15 but the notification still shows 10:11"
    // is the engine restarting with an old serialized snapshot still
    // up on the lock screen). Forcing one sync at boot guarantees the
    // headline matches the page within the first second.
    if (_inBootWindow) {
      await _maybeSyncNotifications(force: true);
    }

    // Heartbeat: every tick, while Active, make sure the foreground
    // service silence keep-alive is still bound. Without this, after
    // the user swipes the activity away the Android OS can reap the
    // FG service quietly on Samsung / Vivo / Xiaomi — the user's
    // exact QA report ("when I close the app it stops playing,
    // notification disappears"). `enterForeground` is idempotent and
    // returns immediately if a clip is already playing.
    try {
      await _coordinator.ensureForegroundForSchedule();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'ScheduleEngine: heartbeat ensureForeground failed: $e\n$st');
      }
    }

    if (_coordinator.snapshot.state == AppPlaybackState.scheduledPlaying &&
        _coordinator.snapshot.isPlaying) {
      // Mid-playback the lock-screen media notification is authoritative;
      // we don't need to refresh the ongoing card. But still keep the
      // sync cadence moving so it re-syncs immediately after the clip
      // ends.
      return;
    }

    // Even on ticks where no slot fires, keep the notification countdown
    // fresh so the schedule page and the notification stay in sync.
    await _maybeSyncNotifications(force: false);

    final all = await _schedules.getAll();
    final now = DateTime.now();

    // Stop tracking any in-flight schedule whose row was deleted or disabled
    // while the clip was playing — otherwise the coordinator would still try
    // to stamp a completion for a schedule that no longer exists.
    final activeId = _coordinator.activeScheduleId;
    if (activeId != null && !all.any((s) => s.id == activeId && s.enabled)) {
      await _coordinator.stop();
    }

    // Round 23 — on Android the native alarm scheduler owns actual
    // fires. Skip the Dart-side firing loop entirely so the two paths
    // can't compete for audio focus mid-slot (that race was the
    // root cause of "later schedules are delayed and eventually stop").
    // The notification / heartbeat / backoff paths above still run.
    if (_delegateFiringToNative) {
      return;
    }

    for (final schedule in all) {
      if (!schedule.enabled) continue;

      // Respect cooldown after a failed fire (empty playlist, unplayable
      // first clip, etc.).
      final backoffUntil = _failureBackoff[schedule.id];
      if (backoffUntil != null && now.isBefore(backoffUntil)) continue;

      final last = _lastFiredForCurrentCycle(schedule, now);
      final lastSlot = _lastSlotForCurrentCycle(schedule, now);
      // Round 19: passing BOTH `last` (completion) AND `lastSlot` (grid
      // start) lets the helper detect whether playback completed cleanly
      // and skip the bogus `+playlistDuration` projection that was making
      // the engine wait an extra playlist-length AFTER the user's
      // expected fire time. The user's exact QA: "schedule shows next at
      // 10:11 but it's 10:15 and nothing played" — that was the engine
      // computing `next = 10:05 (completion) + 5min (duration) + 5min
      // (interval) = 10:15` instead of the correct `10:05 + 5min interval
      // = 10:10`.
      final slot = ScheduleFireHelper.slotToFire(
        schedule,
        now,
        last,
        lastSlot: lastSlot,
        force: force,
      );
      if (slot == null) continue;

      // Round 20: during the boot window, suppress past slots that
      // only fired because of the lateness grace. The user's exact
      // QA ("I opened the app and a clip played 1 minute later even
      // though 7 minutes were left for the next whisper, must have
      // been an old missed slot") was the engine firing a 1-minute-
      // old slot that the helper allowed because of the 2-minute
      // grace. After the boot window has elapsed the engine has been
      // running and the grace serves its real purpose (recovering
      // from a single dropped tick).
      if (!force && _inBootWindow && slot.isBefore(now)) {
        if (kDebugMode) {
          debugPrint(
            'ScheduleEngine: suppressing past slot $slot for ${schedule.id} '
            'inside boot window (force=false) to avoid surprise plays.',
          );
        }
        continue;
      }

      // Skip if another schedule already claimed this exact slot in this
      // cycle. Compare against the GRID slot stamp, not the completion stamp,
      // so the dedup keeps working after we add `setCompletion`.
      if (_slotTakenByOtherSchedule(all, schedule.id, slot)) continue;

      // Round 15: real-time overlap prevention. If ANOTHER schedule is
      // currently playing AND its active window
      // `[startedAt, startedAt + playlistDuration]` overlaps with this
      // schedule's about-to-fire slot, defer THIS schedule by writing
      // the slot stamp (so we don't busy-loop trying to fire it) but
      // NOT the completion stamp (so the engine can re-evaluate on the
      // next tick once the in-flight clip finishes). The user's QA
      // example: a 5-minute playlist starting at 9:00 with 10-minute
      // interval plays at 9:00-9:05, 9:15-9:20, … — any second schedule
      // whose slot lands inside an active 5-minute window must NOT
      // start mid-playlist (overlapping audio is unintelligible).
      final activeScheduleId = _coordinator.activeScheduleId;
      if (activeScheduleId != null && activeScheduleId != schedule.id) {
        final activeSchedule = all.firstWhere(
          (s) => s.id == activeScheduleId,
          orElse: () => schedule,
        );
        if (activeSchedule.id != schedule.id) {
          final activeStarted = _lastFired.slot(activeScheduleId);
          if (activeStarted != null) {
            final activeEnd = activeStarted.add(Duration(
                milliseconds: activeSchedule.playlistDurationMs > 0
                    ? activeSchedule.playlistDurationMs
                    : 60000));
            // Slot falls inside [activeStarted, activeEnd) → defer.
            if (!slot.isBefore(activeStarted) && slot.isBefore(activeEnd)) {
              if (kDebugMode) {
                debugPrint(
                    'ScheduleEngine: deferring ${schedule.id} slot $slot '
                    'because ${activeSchedule.id} is active until '
                    '$activeEnd');
              }
              // Park the slot so we don't busy-poll. The next tick after
              // `activeEnd` will pick up the NEXT slot of this schedule.
              await _lastFired.setSlot(schedule.id, slot);
              continue;
            }
          }
        }
      }

      // Last-chance re-read: between the top of this tick and now (the
      // playlist lookup + slot computations are I/O-bound and can take 10s
      // of ms on cold cache devices) the user might have toggled this
      // schedule OFF. Without this re-check we'd fire a clip the user
      // explicitly just disabled, which they perceive as "the app started
      // playing by itself after I turned the schedule off".
      final fresh = await _schedules.getForPlaylist(schedule.playlistId);
      if (fresh == null || !fresh.enabled) {
        continue;
      }

      // Optimistically stamp the slot start BEFORE asking the coordinator to
      // play. If `requestScheduledPlay` returns false we roll the stamp back
      // so the next tick can retry the same slot inside the grace window.
      await _lastFired.setSlot(schedule.id, slot);
      // Mirror completion so existing `nextSlotAfter` math (which still reads
      // a single timestamp) reflects "we just started this slot". The real
      // completion stamp overwrites this when playback finishes naturally.
      await _lastFired.setCompletion(schedule.id, slot);

      // Defensive: ensure the foreground service is up-and-bound before
      // we ask audio_service to switch from silence-keep-alive to clip
      // playback. The QA report "schedule says NOW but no audio plays"
      // can happen if the OS reclaimed the FG service while the engine
      // was waiting for its next tick — the playFile call then silently
      // no-ops because the underlying media session is detached. We
      // re-enter the foreground binding (idempotent — `enterForeground`
      // is a no-op if already bound) so the schedule fire below always
      // talks to a live service.
      try {
        await _coordinator.ensureForegroundForSchedule();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ScheduleEngine: ensureForegroundForSchedule failed: '
              '$e\n$st');
        }
      }

      // `requestScheduledPlay` can throw on DB lock / coordinator timeout /
      // any other unexpected failure. The stamps above were written
      // optimistically, so we MUST roll them back on EITHER `false` OR a
      // thrown exception — otherwise the engine would treat the slot as
      // honored and the user perceives this as "a schedule disappeared".
      bool played;
      try {
        played = await _coordinator.requestScheduledPlay(
          schedule.playlistId,
          scheduleId: schedule.id,
          shuffle: schedule.shuffleEnabled,
        );
      } catch (e, st) {
        played = false;
        if (kDebugMode) {
          debugPrint(
            'ScheduleEngine: requestScheduledPlay for ${schedule.id} threw: '
            '$e\n$st',
          );
        }
      }

      if (!played) {
        // Roll back the stamps so the engine doesn't think this slot was
        // honored. Apply an EXPONENTIAL backoff so a transient cold-start
        // failure (audio_service still binding) is retried after only 5 s
        // instead of 1 min — that was the QA report that schedules
        // "didn't fire when the app opened with next whisper NOW".
        await _lastFired.clear(schedule.id);
        final streak = (_failureStreak[schedule.id] ?? 0) + 1;
        _failureStreak[schedule.id] = streak;
        final backoff = _backoffFor(streak);
        _failureBackoff[schedule.id] = now.add(backoff);
        debugPrint(
          'ScheduleEngine: schedule ${schedule.id} did not play — '
          'backing off for $backoff (streak=$streak).',
        );
        continue;
      }
      _failureBackoff.remove(schedule.id);
      _failureStreak.remove(schedule.id);

      await onNotificationsSync?.call();
      break;
    }
  }

  /// Calls `onNotificationsSync` if it has been longer than
  /// [_notificationSyncCadence] since the last call (or always when
  /// `force: true`). Each call is independently try/caught so a
  /// notification-channel failure cannot break the tick loop.
  Future<void> _maybeSyncNotifications({required bool force}) async {
    final last = _lastNotificationSync;
    final now = DateTime.now();
    if (!force &&
        last != null &&
        now.difference(last) < _notificationSyncCadence) {
      return;
    }
    _lastNotificationSync = now;
    try {
      await onNotificationsSync?.call();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'ScheduleEngine: periodic notification sync failed: $e\n$st');
      }
    }
  }

  Future<void> _onScheduledCompleted(
    String scheduleId,
    DateTime completedAt,
  ) async {
    await _lastFired.setCompletion(scheduleId, completedAt);
    await onNotificationsSync?.call();
  }

  void _onPlaybackError(PlaybackErrorEvent event) {
    final id = _coordinator.activeScheduleId;
    if (id == null) return;
    // Roll back the stamps so the next tick retries within the grace window
    // instead of waiting for the *next* interval boundary. We deliberately
    // do NOT bump the streak here — `_runTick` does that when it sees
    // `played == false`. Otherwise a single failed fire could
    // double-increment when both code paths run in the same tick.
    _lastFired.clear(id);
    final existingBackoff = _failureBackoff[id];
    if (existingBackoff == null || DateTime.now().isAfter(existingBackoff)) {
      // Only set a default fallback backoff if one isn't already in
      // effect. The proper exponential backoff is applied by `_runTick`.
      _failureBackoff[id] = DateTime.now().add(_baseBackoff);
    }
  }

  /// Slot dedup needs the GRID time, not the completion time. Returns the
  /// `slot` stamp if it's in the current session, else null.
  ///
  /// "Current session" means: same calendar day for daytime schedules, or
  /// inside the active overnight window (e.g. Mon 22:00 stamp is still
  /// current at Tue 03:00 if window is 22:00–06:00).
  DateTime? _lastFiredForCurrentCycle(
    PlaybackSchedule schedule,
    DateTime now,
  ) {
    // Completion-based last fired drives interval-from-end math; this is what
    // `slotToFire` consumes to decide the next grid line. We must keep
    // returning the completion stamp here so a 4-minute playlist on a
    // 5-minute interval still waits 5 minutes after playback ends.
    final completion = _lastFired.completion(schedule.id);
    if (completion == null) return null;
    if (!_sameSessionAs(schedule, completion, now)) return null;
    return completion;
  }

  /// The slot start of the previous fire in the current cycle. Returned
  /// alongside [_lastFiredForCurrentCycle] so the helper can distinguish
  /// "playback already completed (lastFired > lastSlot)" from "still
  /// playing (lastFired == lastSlot, the engine's placeholder)" and
  /// project the next fire time correctly. Without this, the helper
  /// always assumes the previous fire is still in flight and adds an
  /// unnecessary `+playlistDuration` to the next-slot calculation.
  DateTime? _lastSlotForCurrentCycle(
    PlaybackSchedule schedule,
    DateTime now,
  ) {
    final slot = _lastFired.slot(schedule.id);
    if (slot == null) return null;
    if (!_sameSessionAs(schedule, slot, now)) return null;
    return slot;
  }

  bool _sameSessionAs(
    PlaybackSchedule schedule,
    DateTime stamp,
    DateTime now,
  ) {
    // Daytime schedule: same calendar day.
    if (stamp.year == now.year &&
        stamp.month == now.month &&
        stamp.day == now.day) {
      return true;
    }
    // Overnight schedule: stamp from the previous day's start window counts
    // as the same session if we're still inside the wrap-around morning end.
    if (ScheduleFireHelper.isInWindow(schedule, now)) {
      final yesterday = now.subtract(const Duration(days: 1));
      if (stamp.year == yesterday.year &&
          stamp.month == yesterday.month &&
          stamp.day == yesterday.day) {
        return true;
      }
    }
    return false;
  }

  /// True when another enabled schedule already claimed [slot] in its current
  /// session. Compares against the GRID stamp (`slot()`), not the completion
  /// stamp, so the dedup keeps working after the interval-from-end change.
  bool _slotTakenByOtherSchedule(
    List<PlaybackSchedule> all,
    String scheduleId,
    DateTime slot,
  ) {
    for (final other in all) {
      if (other.id == scheduleId || !other.enabled) continue;
      final last = _lastFired.slot(other.id);
      if (last == null) continue;
      if (last.year == slot.year &&
          last.month == slot.month &&
          last.day == slot.day &&
          last.hour == slot.hour &&
          last.minute == slot.minute) {
        return true;
      }
    }
    return false;
  }
}

final scheduleNotificationSyncProvider = Provider<ScheduleNotificationSync>(
  (ref) => () async {
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      prayer: ref.read(prayerRepositoryProvider),
    );
  },
);

final scheduleEngineProvider = Provider<ScheduleEngine>((ref) {
  final engine = ScheduleEngine(
    appStateRepository: ref.watch(appStateRepositoryProvider),
    scheduleRepository: ref.watch(scheduleRepositoryProvider),
    coordinator: ref.watch(playbackCoordinatorProvider),
    lastFiredStore: ScheduleLastFiredStore.instance,
    onNotificationsSync: () => ref.read(scheduleNotificationSyncProvider)(),
  );
  ScheduleEngineBinding.instance.attach(engine.fireNow);
  engine.start();
  ref.onDispose(() {
    engine.stop();
    ScheduleEngineBinding.instance.detach();
  });
  return engine;
});
