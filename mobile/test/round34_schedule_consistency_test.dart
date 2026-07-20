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
      final schedule = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 5,
        playlistDurationMs: 90 * 1000, // 1.5 minutes
      );
      expect(
        ScheduleFireHelper.effectiveStep(schedule),
        const Duration(milliseconds: 5 * 60 * 1000 + 90 * 1000),
        reason: '90s clip + 5m interval must stay exact — rounding to 7m '
            'caused later fires to disagree with NEXT SCHEDULES.',
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
