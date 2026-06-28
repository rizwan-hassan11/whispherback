// Pins the Round 17 critical fixes so future refactors cannot regress
// the user-reported bugs they were designed to address.
//
//   17-A  Scheduling reliability — alarm cap restored to 50 per
//         schedule / 200 global so the OS can wake the device even
//         when the engine isolate has been killed. The Round 16
//         3-alarm cap meant only the FIRST schedule played after a
//         process kill; subsequent fires never happened.
//
//   17-B  Grace window widened to 15 minutes (was 5) so when the
//         user taps the scheduled alarm notification 6-10 minutes
//         after it fired, the engine's cold-start `fireNow` still
//         considers the slot fire-eligible. Below 5 minutes, the
//         user perceived this as "I tapped the notification and
//         nothing happened".
//
//   17-C  All `_player.*Stream` subscriptions in the audio handler
//         have explicit `onError` handlers so an uncaught
//         PlatformException from the native player (Samsung One UI
//         "(-38)", Vivo Funtouch focus revocation) cannot
//         propagate up the stream and crash the activity. This
//         was the actual root cause of "app crashes on rapid
//         pause/resume".
//
//   17-D  `dismissPlayer` is now serialised through the same
//         pause/resume gate. Previously the dismiss path bypassed
//         the gate, allowing rapid pause → cross → cross → play
//         sequences to have overlapping native player calls in
//         flight.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisperback/services/scheduler/schedule_fire_helper.dart';

String _readFile(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    fail('Expected source file does not exist: $relative');
  }
  return f.readAsStringSync();
}

void main() {
  group('Round 17-A — alarm cap covers a real dead-process window', () {
    test('maxAlarmsPerSchedule == 50 (was 3 in Round 16)', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('maxAlarmsPerSchedule = 50'),
        reason: 'Round 16 cut to 3 to defend against ANR, but the side '
            'effect was that only the first scheduled fire after a '
            'process kill played — the user reported "scheduling is '
            'not working entirely". 50 alarms × 5-min interval = '
            '4 hours of coverage even if the engine timer dies the '
            'moment the user closes the app.',
      );
    });

    test('maxAlarmsGlobal == 200', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('maxAlarmsGlobal = 200'),
        reason: 'Global cap supports up to 4 active schedules at full '
            'per-schedule budget. ANR-protected by the `unawaited` '
            'sync in the save flow and the per-call event-loop yield.',
      );
    });

    test('save still unawaits the post-DB notification sync (no ANR risk)',
        () {
      final src =
          _readFile('lib/features/schedule/schedule_builder_screen.dart');
      final saveIdx = src.indexOf('Future<void> _save()');
      expect(saveIdx, greaterThan(0));
      final saveBody = src.substring(saveIdx, saveIdx + 6000);
      expect(
        saveBody,
        contains('unawaited('),
        reason: 'Even with the 200-alarm cap, the save handler MUST '
            'NOT await the notification sync — the binder calls '
            'happen in the background while the UI returns instantly.',
      );
    });

    test('syncSchedules still yields the event loop after every binder call',
        () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      final loopIdx = src.indexOf('for (final slot in ScheduleFireHelper');
      expect(loopIdx, greaterThan(0));
      final loopBody = src.substring(loopIdx, loopIdx + 2400);
      expect(
        loopBody,
        contains('await Future<void>.delayed(Duration.zero);'),
        reason: 'Without the per-call yield, 200 sequential binder '
            'calls would freeze any parallel UI work for ~10s.',
      );
    });
  });

  group('Round 17-B — grace window covers tap-from-alarm delay', () {
    test('maxLateness >= 10 minutes so tapped-late alarms still fire', () {
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        greaterThanOrEqualTo(10),
        reason: 'When the OS killed the process and the user tapped '
            'the alarm notification 6-10 minutes after it fired, the '
            'old 5-minute window made the engine cold-start skip the '
            'slot — the user reported "the notification appears but '
            'no audio plays when I open the app".',
      );
    });

    test('maxLateness <= 30 minutes so we never fire deeply stale slots', () {
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        lessThanOrEqualTo(30),
        reason: 'The grace window must remain bounded so we never fire '
            'a clip the user has long since stopped caring about.',
      );
    });
  });

  group('Round 17-C — player stream errors cannot crash the activity', () {
    test('playbackEventStream subscription has an onError handler', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // The subscription line must be followed by an `onError:` callback.
      final subIdx = src.indexOf('_player.playbackEventStream.listen');
      expect(subIdx, greaterThan(0));
      // Capture the next ~600 chars to include the multi-line call.
      final region = src.substring(subIdx, subIdx + 600);
      expect(
        region,
        contains('onError:'),
        reason: 'Without onError, a PlatformException from the native '
            'player stream propagates up as uncaught and crashes the '
            'audio_service plumbing on Samsung / Vivo (the user-'
            'reported "app crashes on rapid pause/resume").',
      );
    });

    test('durationStream subscription has an onError handler', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final subIdx = src.indexOf('_player.durationStream.listen');
      expect(subIdx, greaterThan(0));
      final region = src.substring(subIdx, subIdx + 500);
      expect(region, contains('onError:'));
    });

    test('positionStream subscription has an onError handler', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final subIdx = src.indexOf('_player.positionStream.listen');
      expect(subIdx, greaterThan(0));
      final region = src.substring(subIdx, subIdx + 700);
      expect(region, contains('onError:'));
    });

    test('coordinator playerStateStream subscription has an onError handler',
        () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final subIdx = src.indexOf('_audio.playerStateStream.listen');
      expect(subIdx, greaterThan(0));
      final region = src.substring(subIdx, subIdx + 700);
      expect(
        region,
        contains('onError:'),
        reason: 'The coordinator-side stream listener must also '
            'swallow errors so an exception in `_onPlayerState` '
            'cannot crash the host activity.',
      );
    });
  });

  group('Round 17-D — dismissPlayer is serialised with pause/resume', () {
    test('dismissPlayer routes through _serializePauseResume', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final dismissIdx = src.indexOf('Future<void> dismissPlayer()');
      expect(dismissIdx, greaterThan(0));
      final body = src.substring(dismissIdx, dismissIdx + 600);
      expect(
        body,
        contains('_serializePauseResume('),
        reason: 'dismissPlayer used to bypass the pause/resume gate — '
            'the user reported crashes when rapidly toggling '
            'pause/resume/cross icon, which traced to overlapping '
            '_audio.pause() calls between the gated pause/resume '
            'path and the un-gated dismissPlayer path.',
      );
    });
  });
}
