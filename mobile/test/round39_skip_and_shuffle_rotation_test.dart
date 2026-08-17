// Round 39 — skip buttons + shuffle one-clip-per-interval.
//
// Two product bugs after the QA scheduling merge:
//   1. Mini-player and notification next/prev did nothing during a
//      scheduled fire because native MediaPlayer had no skip actions
//      and Dart skip talked to idle ExoPlayer.
//   2. Shuffle-on still played the FULL playlist every interval, so
//      a 3-clip playlist blew past the configured gap and drifted
//      the next alarm. Shuffle-on is now one clip per interval,
//      round-robin, with occupancy = max(interval, longest clip).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whisperback/domain/entities/playback_schedule.dart';
import 'package:whisperback/services/scheduler/schedule_fire_helper.dart';

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
}

DateTime _t(int hour, int minute) => DateTime.utc(2020, 1, 6, hour, minute);

PlaybackSchedule _schedule({
  required int intervalMinutes,
  required int playlistDurationMs,
  int maxClipDurationMs = 0,
  bool shuffleEnabled = false,
}) {
  return PlaybackSchedule(
    id: 's1',
    playlistId: 'p1',
    startTime: _t(9, 0),
    endTime: _t(23, 59),
    intervalMinutes: intervalMinutes,
    playlistDurationMs: playlistDurationMs,
    maxClipDurationMs: maxClipDurationMs,
    shuffleEnabled: shuffleEnabled,
  );
}

void main() {
  group('Round 39 — occupancy / effectiveStep', () {
    test('shuffle-off still uses the full playlist duration', () {
      final schedule = _schedule(
        intervalMinutes: 10,
        playlistDurationMs: 15 * 60 * 1000,
        maxClipDurationMs: 5 * 60 * 1000,
      );
      expect(schedule.occupancyDurationMs, 15 * 60 * 1000);
      expect(
        ScheduleFireHelper.effectiveStep(schedule),
        const Duration(minutes: 15),
      );
    });

    test('shuffle-on uses the longest clip, not the playlist sum', () {
      // 3 × 5-minute clips, 15-minute interval. Playing one clip per
      // fire must NOT wait 15 minutes of playlist length — the
      // interval wins (15 > 5) so fires stay on the user's cadence.
      final schedule = _schedule(
        intervalMinutes: 15,
        playlistDurationMs: 15 * 60 * 1000,
        maxClipDurationMs: 5 * 60 * 1000,
        shuffleEnabled: true,
      );
      expect(schedule.occupancyDurationMs, 5 * 60 * 1000);
      expect(
        ScheduleFireHelper.effectiveStep(schedule),
        const Duration(minutes: 15),
      );
    });

    test('shuffle-on waits for a clip longer than the interval', () {
      final schedule = _schedule(
        intervalMinutes: 10,
        playlistDurationMs: 25 * 60 * 1000,
        maxClipDurationMs: 12 * 60 * 1000,
        shuffleEnabled: true,
      );
      expect(
        ScheduleFireHelper.effectiveStep(schedule),
        const Duration(minutes: 12),
      );
    });

    test('shuffle-on with unknown max clip falls back to playlist sum', () {
      final schedule = _schedule(
        intervalMinutes: 10,
        playlistDurationMs: 8 * 60 * 1000,
        maxClipDurationMs: 0,
        shuffleEnabled: true,
      );
      expect(schedule.occupancyDurationMs, 8 * 60 * 1000);
    });
  });

  group('Round 39 — native skip wiring', () {
    test('WhisperPlaybackService exposes skip actions and notification buttons',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('ACTION_SKIP_NEXT'));
      expect(src, contains('ACTION_SKIP_PREVIOUS'));
      expect(src, contains('handleSkipCommand'));
      expect(src, contains('ic_media_previous'));
      expect(src, contains('ic_media_next'));
      expect(src, contains('playSingleClip'));
    });

    test('MainActivity routes skipNativeNext/Previous to the service', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src, contains('"skipNativeNext"'));
      expect(src, contains('"skipNativePrevious"'));
      expect(src, contains('ACTION_SKIP_NEXT'));
      expect(src, contains('ACTION_SKIP_PREVIOUS'));
    });

    test('Dart skip routes to native while MediaPlayer owns playback', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('skipNative(next: next)'));
      expect(src, contains('_nativeOwnsPlayback'));
    });

    test('NativeAlarmsBridge.skipNative calls the platform methods', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains("'skipNative'"));
      expect(src, contains('skipNative({required bool next})'));
      expect(src, contains("'playSingleClip': oneClipPerFire"));
    });
  });

  group('Round 39 — one clip per shuffle interval', () {
    test('native completion does not auto-advance when playSingleClip', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('if (!playSingleClip)'));
    });

    test('Dart scheduled completion skips playlist walk when shuffle is on',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('shuffleThisFire'));
      expect(src, contains('_advanceShuffleCursorAfterFire'));
    });

    test('new playlists default shuffle on', () {
      final src = _read('lib/data/repositories/playlist_repository.dart');
      expect(src, contains("'shuffle_enabled': 1"));
    });

    test('new schedules default shuffle on in the builder', () {
      final src = _read('lib/features/schedule/schedule_builder_screen.dart');
      expect(src, contains('bool _shuffle = true;'));
    });
  });
}
