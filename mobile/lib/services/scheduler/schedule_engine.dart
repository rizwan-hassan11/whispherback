import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/schedule_repository.dart';
import '../../domain/entities/playback_schedule.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../domain/playback/playback_state.dart';
import '../playback/playback_coordinator.dart';

/// Fires scheduled clip playback at interval boundaries.
class ScheduleEngine {
  ScheduleEngine({
    required ScheduleRepository scheduleRepository,
    required PlaybackCoordinator coordinator,
  })  : _schedules = scheduleRepository,
        _coordinator = coordinator;

  final ScheduleRepository _schedules;
  final PlaybackCoordinator _coordinator;
  Timer? _timer;
  final Map<String, DateTime> _lastFired = {};

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _tick() async {
    final snapshot = _coordinator.snapshot;
    if (snapshot.state == AppPlaybackState.manualPlaying) return;

    final all = await _schedules.getAll();
    final now = DateTime.now();
    for (final schedule in all) {
      if (!schedule.enabled) continue;
      if (_shouldFire(schedule, now)) {
        _lastFired[schedule.id] = now;
        await _coordinator.playPlaylist(schedule.playlistId,
            fromSchedule: true);
      }
    }
  }

  bool _shouldFire(PlaybackSchedule schedule, DateTime now) {
    if (!schedule.enabled) return false;
    if (!schedule.runsOnWeekday(now.weekday)) return false;
    if (schedule.startTime.isAfter(now)) return false;

    if (schedule.endTime != null) {
      final endToday = DateTime(
        now.year,
        now.month,
        now.day,
        schedule.endTime!.hour,
        schedule.endTime!.minute,
      );
      if (now.isAfter(endToday)) return false;
    }

    final startToday = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.startTime.hour,
      schedule.startTime.minute,
    );
    if (now.isBefore(startToday)) return false;

    final elapsedMin = now.difference(startToday).inMinutes;
    if (elapsedMin < 0) return false;
    if (elapsedMin % schedule.intervalMinutes != 0) return false;

    // Fire once per interval window (first half of the minute).
    if (now.second >= 30) return false;

    final last = _lastFired[schedule.id];
    if (last != null &&
        now.difference(last).inMinutes < schedule.intervalMinutes) {
      return false;
    }

    return true;
  }
}

final scheduleEngineProvider = Provider<ScheduleEngine>((ref) {
  final engine = ScheduleEngine(
    scheduleRepository: ref.watch(scheduleRepositoryProvider),
    coordinator: ref.watch(playbackCoordinatorProvider),
  );
  ref.onDispose(engine.stop);
  return engine;
});
