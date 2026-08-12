// Round 34 — schedule timing / mini-player / pause consistency guards.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whisperback/domain/entities/playback_schedule.dart';
import 'package:whisperback/services/scheduler/schedule_fire_helper.dart';

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath)).readAsStringSync();
}

DateTime _t(int hour, int minute) =>
    DateTime.utc(2020, 1, 6, hour, minute); // Monday

void main() {
  group('Round 34 — schedule consistency', () {
    test('effectiveStep is millisecond-precise (no minute-rounding drift)', () {
      // Round 36: effectiveStep is max(interval, playlistDuration), not
      // the sum — a 90s clip on a 5-minute interval is well under the
      // interval, so the interval wins outright and the step is exactly
      // 5 minutes (no rounding).
      final shortClip = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 5,
        playlistDurationMs: 90 * 1000, // 1.5 minutes
      );
      expect(
        ScheduleFireHelper.effectiveStep(shortClip),
        const Duration(minutes: 5),
      );
      // When the playlist itself is LONGER than the interval, the
      // playlist's millisecond-precise length wins instead — rounding
      // that to whole minutes caused later fires to disagree with NEXT
      // SCHEDULES.
      final longClip = PlaybackSchedule(
        id: 's2',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 5,
        playlistDurationMs: 7 * 60 * 1000 + 30 * 1000, // 7:30
      );
      expect(
        ScheduleFireHelper.effectiveStep(longClip),
        const Duration(minutes: 7, seconds: 30),
      );
    });

    test('coordinator force-realigns alarms after native completion', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('forceAlarmRebuild: true'));
      expect(src, contains('realign after native fire'));
    });

    test('nativePlaybackProvider polls so mini-player cannot stay hidden', () {
      final src = _read('lib/providers/playback_providers.dart');
      expect(src, contains('Timer.periodic'));
      expect(src, contains('fetchPlaybackState'));
    });

    test('MainActivity keeps stateListener across Activity destroy', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src.contains('stateListener = null'), isFalse,
          reason:
              'Nulling the listener on Activity destroy hid the mini-player.');
    });

    test('alarm snapshot includes effectiveStepMs for native refill', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains("'effectiveStepMs'"));
    });
  });
}
