// Pins the Round 15 critical fixes so future refactors cannot regress
// the user-reported bugs they were designed to address.
//
//   15-A  Rapid pause/play taps must never crash the app. The
//         coordinator now serialises pause+resume through a single
//         async queue, and the audio handler swallows native
//         player exceptions so a PlatformException on one tap can
//         never bubble out and force-close the activity.
//
//   15-B  Mini-player is visible whenever audio is actually playing
//         OR when the snapshot is in a play context. The OLD rule
//         hid it whenever state == activeIdle, which the user
//         observed leave the bar stuck-hidden after `dismissPlayer`
//         even though `playClip` was called again.
//
//   15-C  Interval semantics: gap between fires =
//         `playlistDuration + intervalMinutes`. A 5-minute playlist
//         on a 10-minute interval starting at 1:00 fires at
//         1:00, 1:15, 1:30 — NOT 1:00, 1:10, 1:20.
//
//   15-D  Conflict detection is window-based. Two schedules
//         conflict iff any pair of `[slot, slot+playlistDuration]`
//         windows on shared weekdays overlap. Pure start-time
//         equality is no longer the sole test.
//
//   15-E  Notification fingerprint cache — `syncSchedules` early-
//         returns when the schedule SET hasn't changed since the
//         last call, so the engine's 5-second tick does not
//         re-register up to 60 binder-bound alarms every tick.
//
//   15-F  `enterForeground` is idempotent — it skips the silence
//         loop rebuild when the loop is already running, so the
//         engine heartbeat does not thrash the audio session.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisperback/domain/entities/playback_schedule.dart';
import 'package:whisperback/services/scheduler/schedule_fire_helper.dart';

String _readFile(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    fail('Expected source file does not exist: $relative');
  }
  return f.readAsStringSync();
}

void main() {
  group('Round 15-A — rapid pause/play never crashes', () {
    test('coordinator serialises pause + resume through a single queue', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      expect(
        src,
        contains('_serializePauseResume'),
        reason: 'pause + resume MUST funnel through a single queue '
            'so the user tapping pause/resume rapidly cannot have '
            'overlapping native player calls in flight (the QA '
            'report "app crashes on rapid pause/play").',
      );
      expect(
        src,
        contains('TimeoutException'),
        reason: 'The serialiser must time out hung native calls so a '
            'wedged ExoPlayer state cannot block future taps.',
      );
    });

    test('handler.pause swallows native player exceptions', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // The pause body must catch any error from _player.pause().
      final pauseIdx = src.indexOf('Future<void> pause() async');
      expect(pauseIdx, greaterThan(0));
      final pauseBody = src.substring(pauseIdx, pauseIdx + 1600);
      expect(
        pauseBody,
        contains('await _player.pause();'),
        reason: 'handler.pause must call _player.pause.',
      );
      expect(
        pauseBody,
        contains('catch'),
        reason: 'handler.pause must catch native exceptions so a '
            'Samsung One UI PlatformException ("(-38) '
            'MediaPlayerNative") cannot crash the activity.',
      );
    });

    test('handler.play swallows native player exceptions and does NOT rethrow',
        () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final playIdx = src.indexOf('Future<void> play() async');
      expect(playIdx, greaterThan(0));
      final playBody = src.substring(playIdx, playIdx + 2400);
      // Each potentially-failing step must be independently caught.
      expect(playBody, contains('_ensureAudioSession failed'));
      expect(playBody, contains('setActive failed'));
      expect(
        playBody,
        isNot(contains('rethrow;')),
        reason: 'handler.play must NOT rethrow on _player.play '
            'failure — the coordinator already optimistically '
            'flipped the UI to "playing", and a rethrow would '
            'leave it stuck in that state.',
      );
    });
  });

  group('Round 15-B — mini-player visibility honors actual playback', () {
    test('mini_player_bar uses isPlaying / play-context as visibility gates',
        () {
      final src = _readFile('lib/features/playback/mini_player_bar.dart');
      expect(
        src,
        contains('clipActuallyPlaying'),
        reason: 'mini_player_bar must read the real player state so '
            'the bar shows whenever audio is being heard.',
      );
      expect(
        src,
        contains('AppPlaybackState.scheduledPlaying'),
        reason: 'mini_player_bar must also show in the scheduled '
            'play context.',
      );
      expect(
        src,
        contains('AppPlaybackState.manualPlaying'),
        reason: 'mini_player_bar must show in the manual play '
            'context.',
      );
    });
  });

  group('Round 15-C — interval = playlistDuration + intervalMinutes', () {
    test('effectiveStepMinutes returns duration + interval rounded up', () {
      final schedule = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 10,
        playlistDurationMs: 5 * 60 * 1000,
      );
      expect(
        ScheduleFireHelper.effectiveStepMinutes(schedule),
        15,
        reason: '5-minute playlist + 10-minute interval = 15-minute '
            'step between successive fires.',
      );
    });

    test('effectiveStepMinutes rounds partial minutes UP', () {
      final schedule = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 10,
        playlistDurationMs: 5 * 60 * 1000 + 1, // 5:00.001
      );
      // 5:00.001 ceilings to 6 minutes (the integer rounding is the
      // safe choice — we never want two playlists to butt up against
      // each other to the millisecond).
      expect(ScheduleFireHelper.effectiveStepMinutes(schedule), 16);
    });

    test('effectiveStepMinutes falls back to interval when duration is 0', () {
      final schedule = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        startTime: _t(9, 0),
        endTime: _t(23, 59),
        intervalMinutes: 10,
        playlistDurationMs: 0,
      );
      expect(
        ScheduleFireHelper.effectiveStepMinutes(schedule),
        10,
        reason: 'When the playlist has no clips yet, the helper must '
            'gracefully degrade to interval-only timing instead of '
            'returning 0 and crashing the engine loop.',
      );
    });

    test('intervalAlarmSlots uses the same effective step', () {
      final schedule = PlaybackSchedule(
        id: 's1',
        playlistId: 'p1',
        // Restrict to Monday so we have a deterministic generator.
        daysMask: 1, // Monday only
        startTime: _t(9, 0),
        endTime: _t(9, 45),
        intervalMinutes: 10,
        playlistDurationMs: 5 * 60 * 1000,
      );
      final slots = ScheduleFireHelper.intervalAlarmSlots(schedule).toList();
      final minutes = slots.map((s) => s.hour * 60 + s.minute).toList();
      // 9:00, 9:15, 9:30, 9:45 — step is 15 min, end is exclusive.
      // Whether the last 9:45 is included depends on `!slot.isAfter(end)`
      // which IS inclusive in the existing impl. We only assert that
      // the step BETWEEN successive slots is 15.
      expect(minutes.length, greaterThanOrEqualTo(3));
      for (var i = 1; i < minutes.length; i++) {
        expect(
          minutes[i] - minutes[i - 1],
          15,
          reason: 'Successive intervalAlarmSlots must step by '
              'playlistDuration + intervalMinutes = 15 minutes.',
        );
      }
    });
  });

  group('Round 15-D — conflict detection is window-based', () {
    test('repository computes new schedule duration before conflict check', () {
      final src = _readFile('lib/data/repositories/schedule_repository.dart');
      expect(
        src,
        contains('newDurationMs'),
        reason: 'save() must hydrate the proposed schedule\'s '
            'playlist duration so the conflict check models active '
            'windows for both sides.',
      );
      expect(
        src,
        contains('playlistDurationMs:'),
        reason: '_wouldConflict must be called with the new '
            'schedule\'s duration.',
      );
    });

    test('_wouldConflict computes window overlap on shared weekdays', () {
      final src = _readFile('lib/data/repositories/schedule_repository.dart');
      final idx = src.indexOf('bool _wouldConflict(');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 3500);
      expect(
        body,
        contains('sharedDays'),
        reason: 'Conflict must only test pairs on weekdays both '
            'schedules actually run.',
      );
      expect(
        body,
        contains('existingWindows'),
        reason: 'Both schedules must be expanded into [start, end] '
            'active windows before pairwise overlap testing.',
      );
      expect(
        body,
        contains(r'a.$1 < b.$2 && b.$1 < a.$2'),
        reason: 'Standard half-open interval overlap test.',
      );
    });
  });

  group('Round 15-E — notification fingerprint cache', () {
    test('syncSchedules early-returns when the schedule set is unchanged', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('_lastSyncedFingerprint'),
        reason: 'syncSchedules must cache the last applied schedule '
            'fingerprint so the engine\'s 5-second tick does not '
            're-register all alarms every tick.',
      );
      expect(
        src,
        contains('_fingerprintFor'),
        reason: 'A pure fingerprint helper makes the cache logic '
            'unit-testable.',
      );
    });
  });

  group('Round 15-F — enterForeground is idempotent', () {
    test('enterForeground skips silence loop rebuild when already running', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> enterForeground()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 800);
      expect(
        body,
        contains('_keepAliveRunning && _player.playing'),
        reason: 'enterForeground must skip the silence-loop rebuild '
            'when the loop is already running, so the engine\'s 5-'
            'second heartbeat does not thrash the audio session.',
      );
    });
  });
}

DateTime _t(int hour, int minute) {
  return DateTime.utc(2020, 1, 6, hour, minute); // Monday 2020-01-06
}
