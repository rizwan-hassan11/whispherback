import 'dart:async';

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
  })  : _appState = appStateRepository,
        _schedules = scheduleRepository,
        _coordinator = coordinator,
        _lastFired = lastFiredStore {
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
  Timer? _timer;
  StreamSubscription<PlaybackErrorEvent>? _errorSubscription;

  bool _started = false;
  bool _tickInFlight = false;

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
  static const _failureBackoffDuration = Duration(minutes: 1);

  void start() {
    if (_started) return;
    _timer?.cancel();
    _started = true;
    unawaited(fireNow());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _evictStuckTick();
      unawaited(fireNow());
    });
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _errorSubscription?.cancel();
    _errorSubscription = null;
  }

  bool get isRunning => _started;

  /// Runs one scheduling pass — safe to call from timers, lifecycle, or alarms.
  Future<void> fireNow() async {
    if (!_started || _tickInFlight) return;
    _tickInFlight = true;
    try {
      // Run the tick body; if it never resolves (DB hang, plugin deadlock),
      // a sibling cancellation polls every periodic tick check that
      // `_tickInFlight` hasn't gone stale via `_stuckSince`. Avoids relying
      // on a `Future.timeout` Timer that would otherwise survive a widget
      // test's container dispose and trigger the "pending timers" assert.
      _stuckSince = DateTime.now();
      await _runTick();
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

  Future<void> _runTick() async {
    if (!await _appState.isActive()) return;

    if (_coordinator.snapshot.state == AppPlaybackState.scheduledPlaying &&
        _coordinator.snapshot.isPlaying) {
      return;
    }

    final all = await _schedules.getAll();
    final now = DateTime.now();

    // Stop tracking any in-flight schedule whose row was deleted or disabled
    // while the clip was playing — otherwise the coordinator would still try
    // to stamp a completion for a schedule that no longer exists.
    final activeId = _coordinator.activeScheduleId;
    if (activeId != null && !all.any((s) => s.id == activeId && s.enabled)) {
      await _coordinator.stop();
    }

    for (final schedule in all) {
      if (!schedule.enabled) continue;

      // Respect cooldown after a failed fire (empty playlist, unplayable
      // first clip, etc.).
      final backoffUntil = _failureBackoff[schedule.id];
      if (backoffUntil != null && now.isBefore(backoffUntil)) continue;

      final last = _lastFiredForCurrentCycle(schedule, now);
      final slot = ScheduleFireHelper.slotToFire(schedule, now, last);
      if (slot == null) continue;

      // Skip if another schedule already claimed this exact slot in this
      // cycle. Compare against the GRID slot stamp, not the completion stamp,
      // so the dedup keeps working after we add `setCompletion`.
      if (_slotTakenByOtherSchedule(all, schedule.id, slot)) continue;

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
        // honored. Apply a 1-minute backoff so we don't spin every 5s.
        await _lastFired.clear(schedule.id);
        _failureBackoff[schedule.id] = now.add(_failureBackoffDuration);
        debugPrint(
          'ScheduleEngine: schedule ${schedule.id} did not play — '
          'backing off for $_failureBackoffDuration.',
        );
        continue;
      }
      _failureBackoff.remove(schedule.id);

      await onNotificationsSync?.call();
      break;
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
    // instead of waiting for the *next* interval boundary.
    _lastFired.clear(id);
    _failureBackoff[id] = DateTime.now().add(_failureBackoffDuration);
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
