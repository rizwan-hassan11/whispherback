import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/schedule_repository.dart';
import '../../domain/playback/playback_state.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../playback/playback_coordinator.dart';
import 'schedule_fire_helper.dart';
import 'schedule_last_fired_store.dart';

/// Fires scheduled clip playback at interval boundaries.
class ScheduleEngine {
  ScheduleEngine({
    required ScheduleRepository scheduleRepository,
    required PlaybackCoordinator coordinator,
    required ScheduleLastFiredStore lastFiredStore,
  })  : _schedules = scheduleRepository,
        _coordinator = coordinator,
        _lastFired = lastFiredStore;

  final ScheduleRepository _schedules;
  final PlaybackCoordinator _coordinator;
  final ScheduleLastFiredStore _lastFired;
  Timer? _timer;

  bool _started = false;

  void start() {
    _timer?.cancel();
    _started = true;
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  void stop() {
    _started = false;
    _timer?.cancel();
  }

  bool get isRunning => _started;

  Future<void> _tick() async {
    final snapshot = _coordinator.snapshot;
    if (snapshot.state == AppPlaybackState.manualPlaying) return;
    if (snapshot.isPlaying) return;

    final all = await _schedules.getAll();
    final now = DateTime.now();
    for (final schedule in all) {
      final last = _lastFired.get(schedule.id);
      if (!ScheduleFireHelper.shouldFireNow(schedule, now, last)) continue;

      final slot = ScheduleFireHelper.currentSlot(schedule, now)!;
      await _lastFired.set(schedule.id, slot);
      await _coordinator.requestScheduledPlay(schedule.playlistId);
      break;
    }
  }
}

final scheduleEngineProvider = Provider<ScheduleEngine>((ref) {
  final engine = ScheduleEngine(
    scheduleRepository: ref.watch(scheduleRepositoryProvider),
    coordinator: ref.watch(playbackCoordinatorProvider),
    lastFiredStore: ScheduleLastFiredStore.instance,
  );
  ref.onDispose(engine.stop);
  return engine;
});
