// Pins the Round 14 critical fixes so a future refactor cannot
// accidentally regress the user-reported bugs.
//
//   14-A  Cross icon must PAUSE (not stop) the clip and re-tap on
//         a clip must re-show the mini-player. Round 13 used `stop`,
//         which tore the media session down and confused the resume
//         flow on Android — re-tapping the clip left the player
//         hidden until the user tapped the (stale) lock-screen
//         pause button. We now pause + hide.
//
//   14-B  Save schedule must not ANR/crash even when the schedule
//         table contains many enabled schedules. The previous
//         `syncSchedules` registered every weekly interval slot
//         (capped at 400) which took 20+ seconds and triggered
//         "App Not Responding" on Samsung One UI.
//
//   14-C  Notification headline and schedule page must never show a
//         past time as "next at". `ScheduleFireHelper.nextSlotAfter`
//         now exposes `forDisplay: true` which strips the engine's
//         lateness grace window.
//
//   14-D  Notification headline + schedule page must take the
//         playlist's total duration into account when computing the
//         next slot. The helper now reads `playlistDurationMs` from
//         the schedule entity and `ScheduleRepository.getAll` joins
//         the clips table to populate it.
//
//   14-E  Notification "BigText" summary shows the next 5 upcoming
//         events across all schedules.
//
//   14-F  Engine heartbeat re-binds the foreground service on every
//         5-second tick (while Active is on) so the silence keep-
//         alive can recover from an OEM service-kill while the
//         user has the app minimised.

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
  group('Round 14-A — cross icon hides the player without crashing the app', () {
    test('dismissPlayer is serialised and branches on Active state', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> dismissPlayer()');
      expect(idx, greaterThan(0),
          reason: 'dismissPlayer must remain on the coordinator API.');
      final body = src.substring(idx, idx + 3500);
      // Round 18 contract: the dismiss path now branches.
      //   Active mode → stop the clip player (which transitions
      //     atomically into the silence keep-alive so the FG service
      //     stays bound) — schedules keep firing in the background.
      //   Inactive mode → pause (keeps clip position so user re-tap
      //     resumes from where they left off) — no FG needed since
      //     the user explicitly disabled background work.
      expect(
        body,
        contains('_serializePauseResume'),
        reason: 'dismissPlayer must funnel through the pause/resume '
            'gate so rapid cross/pause taps cannot have two native '
            'player calls in flight at once.',
      );
      expect(
        body,
        contains('wasActive'),
        reason: 'dismissPlayer must check Active state to decide '
            'whether to keep the FG service alive or release it.',
      );
      expect(
        body,
        contains('_audio.pause()'),
        reason: 'The inactive branch must pause so the user can resume '
            'from where they left off on the next clip tap.',
      );
    });
  });

  group('Round 14-B — saving schedules does not ANR / crash', () {
    test(
        'syncSchedules caps the number of registered alarms so it never '
        'serialises 400+ binder calls in a row', () {
      final src = _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('maxAlarmsPerSchedule'),
        reason: 'syncSchedules must enforce a per-schedule cap so a '
            'short interval cannot saturate the global budget on the '
            'far future before the next-up hour is registered.',
      );
      expect(
        src,
        contains('maxAlarmsGlobal'),
        reason: 'syncSchedules must enforce a global cap so the loop '
            'completes within the ANR window.',
      );
      // Per-alarm try/catch so a single revoked-permission failure
      // cannot bubble up and crash the save handler.
      final loopIdx = src.indexOf('intervalAlarmSlots(schedule)');
      expect(loopIdx, greaterThan(0));
      final loopBody = src.substring(loopIdx, loopIdx + 1500);
      expect(
        loopBody,
        contains('try {'),
        reason: 'Each `_scheduleWeekly` call must be wrapped in '
            'try/catch so a single failed alarm does not abort the '
            'entire sync.',
      );
    });
  });

  group('Round 14-C — display never shows past time as "next"', () {
    test('ScheduleFireHelper exposes a forDisplay flag', () {
      final src = _readFile('lib/services/scheduler/schedule_fire_helper.dart');
      expect(
        src,
        contains('bool forDisplay = false'),
        reason: 'forDisplay must be a public-API flag so display call '
            'sites can opt out of the engine grace window.',
      );
      // notification_sync + scheduled_overview + home must pass it.
      final syncSrc =
          _readFile('lib/services/notifications/notification_sync.dart');
      expect(syncSrc, contains('forDisplay: true'),
          reason: 'notification_sync must request display-only mode.');
      final overviewSrc = _readFile(
          'lib/features/schedule/scheduled_overview_screen.dart');
      expect(overviewSrc, contains('forDisplay: true'),
          reason: 'Schedule overview must request display-only mode.');
      final homeSrc = _readFile('lib/features/home/home_screen.dart');
      expect(homeSrc, contains('forDisplay: true'),
          reason: 'Home page subtitle must request display-only mode.');
    });
  });

  group('Round 14-D — next-slot math respects playlist duration', () {
    test(
        'PlaybackSchedule carries playlistDurationMs and the repository '
        'populates it from the clips table', () {
      final entitySrc =
          _readFile('lib/domain/entities/playback_schedule.dart');
      expect(
        entitySrc,
        contains('this.playlistDurationMs'),
        reason: 'Schedule entity must carry the playlist duration so '
            'the helper does interval-from-end math.',
      );
      final repoSrc =
          _readFile('lib/data/repositories/schedule_repository.dart');
      expect(
        repoSrc,
        contains('playlist_duration_ms'),
        reason: 'ScheduleRepository must SUM clip durations into a '
            'playlist_duration_ms column on its SELECT so the entity '
            'is hydrated with the value at load time.',
      );
    });

    test(
        'nextSlotAfter projects end via playlistDurationMs when only the '
        'slot stamp is available', () {
      final src = _readFile('lib/services/scheduler/schedule_fire_helper.dart');
      // Helper must reference playlistDurationMs in its projection math.
      expect(
        src,
        contains('schedule.playlistDurationMs'),
        reason: 'The interval-from-end projection must include the '
            'playlist duration (not just the interval).',
      );
      // It must also distinguish slot vs completion via lastSlot.
      expect(
        src,
        contains('DateTime? lastSlot'),
        reason: 'nextSlotAfter must accept both the slot stamp and '
            'the completion stamp so it can tell "still firing" from '
            '"already completed".',
      );
    });
  });

  group('Round 14-E — notification shows up to 5 upcoming events', () {
    test('notification_sync.dart builds a top-5 upcoming list', () {
      final src =
          _readFile('lib/services/notifications/notification_sync.dart');
      expect(
        src,
        contains('kMaxUpcomingNotification = 5'),
        reason: 'Notification BigText summary must surface at least '
            '5 upcoming entries so the user can verify the schedule '
            'configuration end-to-end from the notification alone.',
      );
    });
  });

  group('Round 14-F — engine heartbeat keeps FG service alive', () {
    test(
        'ScheduleEngine._runTick re-enters the foreground binding every '
        'tick while Active is on', () {
      final src = _readFile('lib/services/scheduler/schedule_engine.dart');
      // Find the _runTick body and confirm it ensures the foreground
      // BEFORE the early-return-on-mid-play branch.
      // Round 19: signature widened to `_runTick({bool force = false})`
      // so the alarm-tap path can bypass the lateness cap. Match either
      // shape so future signature tweaks don't regress this guard.
      var idx = src.indexOf('Future<void> _runTick({bool force = false})');
      if (idx < 0) idx = src.indexOf('Future<void> _runTick()');
      expect(idx, greaterThan(0),
          reason: '_runTick must exist with either the old or new shape.');
      final body = src.substring(idx, idx + 3500);
      // The heartbeat ensureForeground appears BEFORE the "skip if
      // already scheduledPlaying" early-return so the silence keep-
      // alive can be re-bound even when no slot is firing this tick.
      final heartbeatIdx = body.indexOf('ensureForegroundForSchedule');
      final scheduledIdx = body.indexOf('AppPlaybackState.scheduledPlaying');
      expect(heartbeatIdx, greaterThan(0));
      expect(scheduledIdx, greaterThan(0));
      expect(
        heartbeatIdx,
        lessThan(scheduledIdx),
        reason: 'The heartbeat must run BEFORE the mid-play early '
            'return so the silence keep-alive is refreshed even '
            'when no slot is firing.',
      );
    });
  });
}
