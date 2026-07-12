// Pins the Round 19 critical fixes so future refactors cannot regress
// the user-reported bugs they were designed to address.
//
//   19-A  Engine now passes BOTH lastSlot AND lastFired (completion) to
//         `slotToFire` so the next-slot math correctly distinguishes
//         "playback completed cleanly (next = completion + interval)"
//         from "still firing (next = slot + duration + interval)".
//         Without lastSlot the helper always added an extra
//         `playlistDurationMs` to the projection, which matched the
//         user's QA "schedule shows next at 10:11 but it's 10:15 and
//         nothing played".
//
//   19-B  `WhisperAudioHandler` overrides `onTaskRemoved` and
//         `onNotificationDeleted` to keep the silence keep-alive loop
//         running across swipe-away and notification dismissal. Without
//         these, audio_service quietly demoted the FG service within
//         seconds of the user closing the app — the user's QA "audio
//         was killed when I closed the app, no notification of
//         pause/resume" was the FG service teardown letting the OS
//         reap the process.
//
//   19-C  `ScheduleEngineBinding.fireNow(force: true)` from the alarm
//         action lets a slot fire even if the OS missed it by more
//         than `maxLateness`. The general lateness cap is now back
//         down to 2 minutes (Round 17's 15-min widening caused
//         phantom plays), and the alarm-tap path handles the
//         tap-late case explicitly.
//
//   19-D  `maxLateness = 2 minutes`. Round 17's 15-min cap let
//         missed-but-not-too-old slots ambush the user the moment
//         they opened the app ("7 minutes remaining for next whisper
//         but after 1 minute the clip played automatically").
//
//   19-E  Schedule overview screen renders a compact "upcoming
//         fires" table (up to 5 slots across all enabled schedules)
//         instead of only showing the next single fire.

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

PlaybackSchedule _buildSchedule({
  required int startHour,
  required int startMinute,
  required int intervalMinutes,
  int playlistDurationMs = 0,
  int? endHour,
  int? endMinute,
  int daysMask = 127,
}) {
  return PlaybackSchedule(
    id: 'test-${startHour}_$startMinute',
    playlistId: 'pl-test',
    playlistName: 'Test playlist',
    startTime: DateTime(2020, 1, 1, startHour, startMinute),
    endTime:
        endHour != null ? DateTime(2020, 1, 1, endHour, endMinute ?? 0) : null,
    intervalMinutes: intervalMinutes,
    daysMask: daysMask,
    enabled: true,
    alarmEnabled: true,
    playlistDurationMs: playlistDurationMs,
  );
}

void main() {
  group('Round 19-A — engine passes lastSlot for accurate slot math', () {
    test('engine reads _lastSlotForCurrentCycle and passes it to slotToFire',
        () {
      final src = _readFile('lib/services/scheduler/schedule_engine.dart');
      expect(
        src,
        contains('_lastSlotForCurrentCycle'),
        reason: 'The engine must read the slot stamp (in addition to '
            'the completion stamp) so the helper can tell "still '
            'playing" from "already completed".',
      );
      expect(
        src,
        contains('lastSlot: lastSlot'),
        reason: '_runTick must forward both lastFired and lastSlot to '
            'ScheduleFireHelper.slotToFire so the next-slot projection '
            'does not over-add an unnecessary playlist duration.',
      );
    });

    test(
        'a 5-min playlist on 5-min interval, completed at 10:05, fires '
        'next at 10:10 — NOT 10:15', () {
      final schedule = _buildSchedule(
        startHour: 10,
        startMinute: 0,
        intervalMinutes: 5,
        playlistDurationMs: 5 * 60 * 1000,
      );
      // Slot started 10:00, completed cleanly at 10:05.
      final lastSlot = DateTime(2026, 6, 28, 10, 0);
      final completion = DateTime(2026, 6, 28, 10, 5);
      final next = ScheduleFireHelper.nextFireTime(
        schedule,
        DateTime(2026, 6, 28, 10, 5, 30),
        lastFired: completion,
        lastSlot: lastSlot,
      );
      expect(
        next,
        DateTime(2026, 6, 28, 10, 10),
        reason: 'When the completion stamp is known to be later than '
            'the slot stamp, the helper must treat the previous fire '
            'as "completed" (next = completion + interval) instead '
            'of "still firing" (next = slot + duration + interval).',
      );
    });

    test(
        'placeholder case: lastFired == lastSlot means the fire is still '
        'in flight — helper projects end via playlistDurationMs', () {
      final schedule = _buildSchedule(
        startHour: 10,
        startMinute: 0,
        intervalMinutes: 5,
        playlistDurationMs: 4 * 60 * 1000, // 4 min playlist
      );
      // Engine wrote the placeholder (slot == fired) at 10:00. Playback
      // is still in flight at 10:02.
      final placeholder = DateTime(2026, 6, 28, 10, 0);
      final next = ScheduleFireHelper.nextFireTime(
        schedule,
        DateTime(2026, 6, 28, 10, 2),
        lastFired: placeholder,
        lastSlot: placeholder,
      );
      // Projected end ≈ 10:00 + 4 min = 10:04. Next = 10:04 + 5 min = 10:09.
      expect(
        next,
        DateTime(2026, 6, 28, 10, 9),
        reason: 'When the completion stamp matches the slot stamp '
            '(placeholder), the helper projects the end via '
            'playlistDurationMs so the next fire still lands after '
            'the silent gap the user configured.',
      );
    });
  });

  group('Round 19-B — handler keeps silence alive across task removal', () {
    test('WhisperAudioHandler overrides onTaskRemoved', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      expect(
        src,
        contains('Future<void> onTaskRemoved()'),
        reason: 'Without an explicit override, audio_service quietly '
            'demotes the FG service inside ~60 s of swipe-away on '
            'Samsung/Vivo/Xiaomi and the user reports "audio cuts '
            'when I close the app".',
      );
    });

    test('WhisperAudioHandler overrides onNotificationDeleted', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      expect(
        src,
        contains('Future<void> onNotificationDeleted()'),
        reason: 'The base implementation calls stop() which tears down '
            'the silence keep-alive. We must re-establish it when '
            'Active is ON so the user can never silently disable '
            'background scheduling by swiping a notification card.',
      );
    });

    test('onTaskRemoved restarts the silence loop when keep-alive is on', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> onTaskRemoved()');
      expect(idx, greaterThan(0));
      // The body must reference _startIdleKeepAlive to truly re-bind
      // the FG service after a swipe-away.
      final body = src.substring(idx, idx + 2000);
      expect(
        body,
        contains('_startIdleKeepAlive'),
        reason: 'onTaskRemoved must explicitly restart the silence '
            'loop so audio_service has a fresh `playing: true` event '
            'to keep the service bound to FG.',
      );
    });
  });

  group('Round 19-C — alarm-tap forces a fire even when late', () {
    test('NotificationService passes force: true when alarm is tapped', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('ScheduleEngineBinding.instance.fireNow(force: true)'),
        reason: 'A user who taps a late alarm explicitly expects the '
            'audio to play, even if the OS missed the slot by more '
            'than maxLateness. Without force, the engine silently '
            'no-ops and the user files a "tap did nothing" bug.',
      );
    });

    test('engine fireNow accepts the force flag', () {
      final src = _readFile('lib/services/scheduler/schedule_engine.dart');
      expect(
        src,
        contains('Future<void> fireNow({bool force = false})'),
        reason: 'The fireNow API must expose `force` so the alarm-tap '
            'path can bypass the lateness cap.',
      );
    });

    test('engine binding signature carries the force flag', () {
      final src =
          _readFile('lib/services/scheduler/schedule_engine_binding.dart');
      expect(
        src,
        contains('Future<void> fireNow({bool force = false})'),
        reason: 'The binding (used by notification entry points) must '
            'expose the same force flag as the engine.',
      );
    });

    test('cold-start passes force=true when launched from a schedule alarm',
        () {
      final src = _readFile('lib/app.dart');
      expect(
        src,
        contains('launchedFromScheduleAlarm'),
        reason: 'app.dart must consult NotificationService to detect '
            'whether the cold start came from a tap on a scheduled '
            'alarm notification.',
      );
      expect(
        src,
        contains('fireNow(force: fromAlarm)'),
        reason: 'When the cold start is alarm-initiated the engine '
            'must fire with force=true so the slot the user came for '
            'plays even if it is older than maxLateness.',
      );
    });
  });

  group('Round 19-D — maxLateness reverted to a tight 2 minutes', () {
    test('maxLateness <= 5 minutes (was 15 in Round 17)', () {
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        lessThanOrEqualTo(5),
        reason: 'The Round 17 widening to 15 minutes surfaced as the '
            'user QA "after 1 minute the clip played automatically — '
            'must have been a missed previous schedule". The tap-late '
            'scenario is now handled by `force: true` in fireNow.',
      );
    });

    test('maxLateness >= 1 minute so a single tick drop is absorbed', () {
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        greaterThanOrEqualTo(1),
        reason: 'A 30-60 s engine stutter (Doze pause, audio_service '
            'rebind) must not silently skip the slot.',
      );
    });
  });

  group('Round 19-E — schedule overview shows upcoming fires table', () {
    test('overview screen renders a _UpcomingFiresList widget', () {
      final src =
          _readFile('lib/features/schedule/scheduled_overview_screen.dart');
      expect(
        src,
        contains('_UpcomingFiresList'),
        reason: 'The page must list multiple upcoming fires (not just '
            'the single next one) so the user can verify their '
            'scheduling end-to-end without scrubbing each card.',
      );
      expect(
        src,
        contains('ScheduleFireHelper.upcomingEvents'),
        reason: 'The upcoming list MUST be sourced from '
            'upcomingEvents so it uses the same interval-from-end + '
            'last-fired-aware math as the engine.',
      );
    });

    test('upcomingEvents uses effectiveStepMinutes (not raw interval)', () {
      // A 5-min playlist on a 5-min interval starting 10:00 should
      // produce 10:00, 10:10, 10:20 (step = 10 min), not 10:00, 10:05,
      // 10:10 (step = 5 min — would overlap playlist with silent gap).
      final schedule = _buildSchedule(
        startHour: 10,
        startMinute: 0,
        intervalMinutes: 5,
        playlistDurationMs: 5 * 60 * 1000,
      );
      final events = ScheduleFireHelper.upcomingEvents(
        [schedule],
        DateTime(2026, 6, 28, 9, 30),
        limit: 3,
      );
      expect(events.length, 3);
      expect(events[0].when, DateTime(2026, 6, 28, 10, 0));
      expect(events[1].when, DateTime(2026, 6, 28, 10, 10));
      expect(events[2].when, DateTime(2026, 6, 28, 10, 20));
    });
  });
}
