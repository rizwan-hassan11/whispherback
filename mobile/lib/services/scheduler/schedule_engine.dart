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

  bool _started = false;

  void start() {
    _timer?.cancel();
    _started = true;
    // Fire an immediate check so playback can begin the moment the app opens
    // inside an active window, then poll on a short interval.
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  void stop() {
    _started = false;
    _timer?.cancel();
  }

  bool get isRunning => _started;

  Future<void> _tick() async {
    // Don't interrupt a clip the user started manually.
    final snapshot = _coordinator.snapshot;
    if (snapshot.state == AppPlaybackState.manualPlaying) return;
    // Already playing a scheduled clip — let it finish.
    if (snapshot.isPlaying) return;

    final all = await _schedules.getAll();
    final now = DateTime.now();
    for (final schedule in all) {
      if (!_shouldFire(schedule, now)) continue;
      _lastFired[schedule.id] = now;
      await _coordinator.playPlaylist(schedule.playlistId, fromSchedule: true);
      // Only one schedule fires per tick.
      break;
    }
  }

  bool _shouldFire(PlaybackSchedule schedule, DateTime now) {
    if (!schedule.enabled) return false;
    if (!schedule.runsOnWeekday(now.weekday)) return false;

    final startToday = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.startTime.hour,
      schedule.startTime.minute,
    );
    if (now.isBefore(startToday)) return false;

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

    final last = _lastFired[schedule.id];
    if (last == null) {
      // First eligible check inside the window — start immediately.
      return true;
    }
    // Otherwise fire once per interval since the last play.
    return now.difference(last).inMinutes >= schedule.intervalMinutes;
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
