import 'dart:async';

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
        _lastFired = lastFiredStore;

  final AppStateRepository _appState;
  final ScheduleRepository _schedules;
  final PlaybackCoordinator _coordinator;
  final ScheduleLastFiredStore _lastFired;
  final ScheduleNotificationSync? onNotificationsSync;
  Timer? _timer;

  bool _started = false;
  bool _tickInFlight = false;

  void start() {
    if (_started) return;
    _timer?.cancel();
    _started = true;
    unawaited(fireNow());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(fireNow()));
  }

  void stop() {
    _started = false;
    _timer?.cancel();
  }

  bool get isRunning => _started;

  /// Runs one scheduling pass — safe to call from timers, lifecycle, or alarms.
  Future<void> fireNow() async {
    if (!_started || _tickInFlight) return;
    _tickInFlight = true;
    try {
      if (!await _appState.isActive()) return;

      if (_coordinator.snapshot.state == AppPlaybackState.scheduledPlaying &&
          _coordinator.snapshot.isPlaying) {
        return;
      }

      final all = await _schedules.getAll();
      final now = DateTime.now();

      for (final schedule in all) {
        if (!schedule.enabled) continue;

        final last = _lastFiredForToday(schedule.id, now);
        final slot = ScheduleFireHelper.slotToFire(schedule, now, last);
        if (slot == null) continue;

        // Skip if another schedule already claimed this exact slot.
        if (_slotTakenByOtherSchedule(all, schedule.id, slot, now)) continue;

        final played =
            await _coordinator.requestScheduledPlay(schedule.playlistId);
        if (!played) continue;

        await _lastFired.set(schedule.id, slot);
        await onNotificationsSync?.call();
        break;
      }
    } finally {
      _tickInFlight = false;
    }
  }

  /// Ignore stale [lastFired] from a previous calendar day.
  DateTime? _lastFiredForToday(String scheduleId, DateTime now) {
    final last = _lastFired.get(scheduleId);
    if (last == null) return null;
    if (last.year != now.year ||
        last.month != now.month ||
        last.day != now.day) {
      return null;
    }
    return last;
  }

  /// True when another enabled schedule already fired at [slot] today.
  bool _slotTakenByOtherSchedule(
    List<PlaybackSchedule> all,
    String scheduleId,
    DateTime slot,
    DateTime now,
  ) {
    for (final other in all) {
      if (other.id == scheduleId || !other.enabled) continue;
      final last = _lastFiredForToday(other.id, now);
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
