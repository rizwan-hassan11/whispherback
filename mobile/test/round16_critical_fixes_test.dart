// Pins the Round 16 critical fixes so future refactors cannot regress
// the user-reported bugs they were designed to address.
//
//   16-A  Schedule SAVE never blocks the UI thread.
//         `syncSchedules` registrations are aggressively capped (3 per
//         schedule, 20 global) and yield the event loop after EVERY
//         binder call. `schedule_builder_screen` `unawaited`s the
//         post-save notification sync so the spinner clears
//         instantly.
//
//   16-B  Silence keep-alive uses inaudible-but-non-zero volume
//         (0.001) and a longer 10-second silence file so OEM audio
//         policy daemons keep the foreground service truly alive
//         when the activity is destroyed. Volume 0 + 1-second loop
//         was being misclassified as "not playing" on Samsung /
//         Vivo / Xiaomi.
//
//   16-C  Status notification uses Importance.defaultImportance so
//         it cannot be silently auto-collapsed by aggressive OEM
//         notification managers.
//
//   16-D  playFile pre-publishes a `playing: true` PlaybackState
//         BEFORE setAudioSource so audio_service calls
//         `Service.startForeground()` immediately and the OS cannot
//         reap the service before the player event loop ticks.
//
//   16-E  Scheduled alarm notifications expose a "Play now" action
//         so a user who tapped the alarm action wakes the engine
//         even when the app process was killed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFile(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    fail('Expected source file does not exist: $relative');
  }
  return f.readAsStringSync();
}

void main() {
  group('Round 16-A — schedule save never blocks the UI thread', () {
    test('syncSchedules cap covers many hours of upcoming fires', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      // Round 17: bumped from 3/20 (Round 16) to 50/200 because the
      // engine timer dies when the OS kills the process. We need
      // many pre-registered OS alarms to cover the dead-process
      // window. ANR is no longer a concern because the post-save
      // sync is `unawaited` and yields the event loop after every
      // binder call (covered by separate tests).
      expect(
        src,
        contains('maxAlarmsPerSchedule = 50'),
        reason: 'A 50-alarm cap covers ~4 hours of 5-minute interval '
            'fires per schedule even when the engine is dead.',
      );
      expect(
        src,
        contains('maxAlarmsGlobal = 200'),
        reason: 'Global cap of 200 supports up to 4 active schedules '
            'at full per-schedule budget while still keeping the '
            'unawaited binder calls bounded.',
      );
    });

    test('syncSchedules yields the event loop after every binder call', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      // The yield must appear inside the per-slot loop.
      final loopIdx = src.indexOf('for (final slot in ScheduleFireHelper');
      expect(loopIdx, greaterThan(0));
      final loopBody = src.substring(loopIdx, loopIdx + 2200);
      expect(
        loopBody,
        contains('await Future<void>.delayed(Duration.zero);'),
        reason: 'Without an event-loop yield between binder calls, the '
            'UI thread is starved for the entire save flow and the '
            'spinner appears hung even though the save itself ran.',
      );
    });

    test(
        'schedule builder unawaits the post-save notification sync so save '
        'completes instantly', () {
      final src =
          _readFile('lib/features/schedule/schedule_builder_screen.dart');
      // The save handler must NOT await syncWhisperNotifications.
      final saveIdx = src.indexOf('Future<void> _save()');
      expect(saveIdx, greaterThan(0));
      final saveBody = src.substring(saveIdx, saveIdx + 6000);
      expect(
        saveBody,
        contains('unawaited('),
        reason: 'syncWhisperNotifications must be fire-and-forget after '
            'the DB write so the user sees the success dialog the '
            'instant the save row commits.',
      );
      expect(
        saveBody,
        contains('syncWhisperNotifications('),
        reason: 'The save flow must still trigger the notification '
            'refresh — just not await it.',
      );
    });
  });

  group('Round 16-B — silence keep-alive truly elevates the FG service', () {
    test('silence keep-alive uses inaudible-but-non-zero volume', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final startIdx = src.indexOf('Future<void> _startIdleKeepAlive()');
      expect(startIdx, greaterThan(0));
      final body = src.substring(startIdx, startIdx + 2500);
      expect(
        body,
        contains('_player.setVolume(0.001)'),
        reason: 'OEM audio policy daemons on Samsung / Vivo / Xiaomi '
            'revoke focus when they see volume == 0. 0.001 is '
            'mathematically inaudible (-60 dB) but counts as real '
            'playback.',
      );
    });

    test('silence file is 10 seconds long (v2 path)', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      expect(
        src,
        contains("whisperback_session_silence_v2.wav"),
        reason: 'Bumping the cached filename forces existing installs '
            'to write the longer file (the 1-second one shipped pre-'
            'Round 16 was being misclassified as "not playing" on '
            'some firmware).',
      );
      expect(
        src,
        contains('int seconds = 10'),
        reason: 'The silent WAV must default to 10 seconds so the loop '
            'turns over only every 10 seconds, well below the rate at '
            'which OEM focus daemons sample.',
      );
    });
  });

  group('Round 16-C — status notification cannot be auto-collapsed', () {
    test('status channel uses Importance.defaultImportance', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      // Locate the status-channel registration.
      final channelIdx = src.indexOf("_statusChannelId,\n        'Active status'");
      expect(channelIdx, greaterThan(0));
      final channelBody = src.substring(channelIdx, channelIdx + 800);
      expect(
        channelBody,
        contains('Importance.defaultImportance'),
        reason: 'Importance.low got auto-collapsed by Samsung One UI / '
            'MIUI / Funtouch — the user reported the notification '
            'disappeared even with Active ON. defaultImportance keeps '
            'the status-bar icon visible silently.',
      );
    });

    test('showActiveOngoing matches the channel importance', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      final showIdx = src.indexOf('Future<void> showActiveOngoing(');
      expect(showIdx, greaterThan(0));
      final body = src.substring(showIdx, showIdx + 2400);
      expect(
        body,
        contains('Importance.defaultImportance'),
        reason: 'Per-notification importance must match the channel '
            'to defend against OEMs that ignore the channel-level '
            'setting.',
      );
      expect(
        body,
        contains('Priority.defaultPriority'),
        reason: 'Pre-channel-API priority must also match for legacy '
            'Android paths.',
      );
    });
  });

  group('Round 16-D — playFile starts FG service before setAudioSource', () {
    test('playFile pre-publishes a playing-true PlaybackState', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final playFileIdx = src.indexOf('Future<void> playFile(');
      expect(playFileIdx, greaterThan(0));
      // Capture the PRE-setAudioSource portion only (everything up to
      // the first setAudioSource call INSIDE playFile).
      final setSourceIdx =
          src.indexOf('.setAudioSource(AudioSource.file(path)', playFileIdx);
      expect(setSourceIdx, greaterThan(playFileIdx));
      final preBody = src.substring(playFileIdx, setSourceIdx);
      expect(
        preBody,
        contains('playbackState.add('),
        reason: 'A playing-true PlaybackState must be published BEFORE '
            'setAudioSource so audio_service calls '
            'Service.startForeground() immediately and the OS cannot '
            'reap the service mid-load.',
      );
      expect(
        preBody,
        contains('playing: true'),
        reason: 'The pre-flight state MUST flag playing: true so the '
            'audio_service native side elevates to FG.',
      );
      expect(
        preBody,
        contains('AudioProcessingState.loading'),
        reason: 'The pre-flight state should report loading so the '
            'media notification shows a spinner while the source '
            'attaches.',
      );
    });
  });

  group('Round 16-E — scheduled alarm exposes a Play now action', () {
    test('_scheduleWeekly includes a schedule_play_now action', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      final schedIdx = src.indexOf('Future<void> _scheduleWeekly(');
      expect(schedIdx, greaterThan(0));
      final body = src.substring(schedIdx, schedIdx + 2400);
      expect(
        body,
        contains("'schedule_play_now'"),
        reason: 'The scheduled-alarm notification must expose a '
            '"Play now" action so a user whose app was killed by the '
            'OS can wake the engine with a single tap.',
      );
      expect(
        body,
        contains('showsUserInterface: true'),
        reason: 'The action must launch the activity (which auto-'
            'revives the Dart isolate and resumes the engine).',
      );
    });

    test('_onNotificationResponse routes schedule_play_now to the engine',
        () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      final respIdx = src.indexOf('_onNotificationResponse(');
      expect(respIdx, greaterThan(0));
      final body = src.substring(respIdx, respIdx + 900);
      expect(
        body,
        contains("'schedule_play_now'"),
        reason: 'The response handler must wake the engine when the '
            'Play now action is tapped.',
      );
      expect(
        body,
        contains('ScheduleEngineBinding.instance.fireNow()'),
        reason: 'The engine binding must be invoked so a fresh '
            'scheduling pass starts.',
      );
    });
  });
}
