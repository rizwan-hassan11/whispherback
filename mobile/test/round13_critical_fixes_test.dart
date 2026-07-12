// Regression suite for Round 13 fixes. Each test pins a code-level
// invariant that, if broken, brings back a specific QA report verbatim:
//
//   13-A  "When I tap the cross icon on the mini-player / modal, the app
//          STILL crashes / closes" → caused by the cross-icon wiring
//          to `coordinator.stop()`, which on standalone playback used
//          to call `super.stop()` (now removed in Round 12) but on the
//          keep-alive path STILL went through `_audio.stop` →
//          `stopClip` → which on some OEMs can still throw during
//          the second-tap teardown race. The new `dismissPlayer()`
//          method bypasses the whole top-level `stop` path and is
//          wired to the cross icon directly.
//
//   13-B  "I set a 100-minute interval and ANY second schedule shows
//          a conflict error" → caused by the old `_wouldConflict`
//          comparing every clock-grid slot of one schedule against
//          every slot of the other and flagging ANY pair within 30s.
//          With a 100-min interval, that's ~15 slots per day; with a
//          5-min interval the other has ~288. 4320 pairs guaranteed
//          a collision. The new check only flags TRUE start-time
//          conflicts (within 1 minute) on overlapping days.
//
//   13-C  "Notification bar shows 'next at X' but the schedule page
//          shows 'next at Y' (different values)" → caused by the
//          notification only being re-synced after a fire (which can
//          be 10s of minutes apart), while the page re-renders its
//          countdown every 30s. The engine now re-syncs the
//          notification every 30s alongside its tick cadence so the
//          two surfaces stay aligned.
//
//   13-D  "Schedule shows NOW but no audio plays" → caused by the OS
//          reclaiming the audio_service foreground service while the
//          engine was waiting between ticks. The next fire calls
//          `_audio.playFile` on a detached media session and silently
//          no-ops. The engine now calls
//          `coordinator.ensureForegroundForSchedule()` immediately
//          before each fire so the FG service is guaranteed to be
//          re-bound when the schedule fire begins.
//
//   13-E  Conflict dialog surfaces a one-tap "Use ${time}" suggestion
//          so the user is never stuck — the repository's `save()`
//          method walks forward 1 minute at a time up to 4 hours to
//          find the first non-conflicting start time and attaches it
//          to the thrown `ScheduleConflictException`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFile(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue,
      reason: 'Expected source file at $relativePath');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  group('Round 13-A — cross icon is wired to dismissPlayer not stop', () {
    test(
        'mini_player_bar.dart cross icon calls `coordinator.dismissPlayer` '
        'instead of `coordinator.stop` (which on some OEMs can still throw '
        'during the second-tap teardown race)', () {
      final src = _readFile('lib/features/playback/mini_player_bar.dart');
      // Find the cross icon block and assert it routes to dismissPlayer.
      final crossIdx = src.indexOf('icon: AppIcons.close,');
      expect(crossIdx, greaterThan(0),
          reason: 'Cross icon button is missing from the mini-player.');
      // Take the surrounding 800 chars (the cross icon definition).
      final region = src.substring(crossIdx, crossIdx + 800);
      expect(
        region,
        contains('coordinator.dismissPlayer'),
        reason: 'Cross icon must invoke dismissPlayer — the new method '
            'that pauses + hides WITHOUT calling audio_service.stop. '
            'QA report "tapping cross closes the app" was the OEM '
            'activity-kill risk inside the stop() path.',
      );
    });

    test(
        'playback_modal.dart cross icon also uses dismissPlayer for the same '
        'reason', () {
      final src = _readFile('lib/features/playback/playback_modal.dart');
      final crossIdx = src.indexOf('icon: AppIcons.close,');
      expect(crossIdx, greaterThan(0),
          reason: 'Cross icon button is missing from the modal.');
      final region = src.substring(crossIdx, crossIdx + 800);
      expect(
        region,
        contains('coordinator.dismissPlayer'),
        reason: 'Modal cross icon must also invoke dismissPlayer.',
      );
    });

    test(
        'PlaybackCoordinator.dismissPlayer exists and routes through the '
        'pause/resume serializer for crash safety', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      final dismissIdx = src.indexOf('Future<void> dismissPlayer()');
      expect(dismissIdx, greaterThan(0),
          reason: 'dismissPlayer method is missing from the coordinator.');
      // Round 22 — bumped from 3500 chars to 6000 because the body
      // grew to include the native-scheduled-playback bypass branch.
      // The substring assertions still hold; we just need a wider
      // window because `_audio.pause()` is now further down.
      final body = src.substring(
        dismissIdx,
        (dismissIdx + 6000).clamp(0, src.length),
      );
      // Round 18 contract: branch on wasActive so the FG service stays
      // alive in Active mode (clip→silence atomic handoff via stop()
      // when keep-alive is set) and the process is fully released in
      // Inactive mode (pause keeps clip position for resume).
      expect(
        body,
        contains('_audio.pause()'),
        reason: 'dismissPlayer inactive branch must pause the player '
            'so clip position is preserved.',
      );
      expect(
        body,
        contains('_serializePauseResume'),
        reason: 'dismissPlayer must funnel through the same gate as '
            'pause/resume so rapid cross/pause taps cannot race '
            'overlapping native player calls.',
      );
      expect(
        body,
        contains('AppPlaybackState.activeIdle'),
        reason: 'dismissPlayer must transition the snapshot back to '
            'activeIdle (or inactive) so both the mini-player and the '
            'modal visibility checks hide them.',
      );
    });
  });

  group('Round 13-B — schedule conflict check no longer false-positives', () {
    test(
        '_wouldConflict only flags conflicts when start-times are within 1 '
        'minute on overlapping days (no more all-pairs clock-grid scan)', () {
      final src = _readFile('lib/data/repositories/schedule_repository.dart');
      // The old all-pairs scan path must be gone. Look for the old loop
      // structure that compared every existingSlot against every newSlot.
      expect(
        src,
        isNot(contains('for (final a in existingSlots)')),
        reason: 'The old all-pairs clock-grid scan was the false-positive '
            'source. QA report "100-min interval + ANY second schedule '
            '= conflict error" was generated by ~4320 slot pairs almost '
            'always producing a pair within 30 seconds.',
      );
      // Round 15 update: the conflict check is now WINDOW-based
      // (start-time + playlistDuration) rather than start-time-only.
      // The Round 13 contract (`delta < 1`) is intentionally superseded
      // — see round15_critical_fixes_test for the new contract.
      expect(
        src,
        contains('sharedDays'),
        reason: 'Round 15 conflict check must restrict to shared '
            'weekdays before expanding active windows.',
      );
      expect(
        src,
        contains('existingWindows'),
        reason: 'Both schedules expanded into [start, end] active '
            'windows for pairwise overlap testing.',
      );
    });

    test(
        'ScheduleConflictException now carries a `suggestedStartTime` so '
        'the UI can surface a one-tap "Use ${"{time}"}" action', () {
      final src = _readFile('lib/data/repositories/schedule_repository.dart');
      expect(
        src,
        contains('final DateTime? suggestedStartTime;'),
        reason: 'ScheduleConflictException must expose a suggested start '
            'time so the conflict dialog is never a dead-end.',
      );
      expect(
        src,
        contains('_suggestNonConflictingStart('),
        reason: 'The repository must compute a suggestion before throwing.',
      );
    });

    test(
        'conflict dialog in schedule_builder_screen offers the suggestion '
        'as a one-tap action that re-attempts the save automatically', () {
      final src =
          _readFile('lib/features/schedule/schedule_builder_screen.dart');
      expect(
        src,
        contains('l10n.scheduleUseSuggestion'),
        reason: 'Dialog must surface the "Use suggestion" button.',
      );
      expect(
        src,
        contains('await _save();'),
        reason: 'Accepting the suggestion must re-trigger the save flow '
            'transparently — no double-tap UX.',
      );
    });
  });

  group('Round 13-C — engine re-syncs notifications every 30 seconds', () {
    test(
        'ScheduleEngine._runTick calls _maybeSyncNotifications on every '
        'tick (including the inactive-toggle path) so the persistent '
        'notification headline never drifts more than 30s from the '
        'schedule page countdown', () {
      final src = _readFile('lib/services/scheduler/schedule_engine.dart');
      expect(
        src,
        contains('await _maybeSyncNotifications(force: false);'),
        reason: '_runTick must call _maybeSyncNotifications proactively.',
      );
      expect(
        src,
        contains(
            'static const _notificationSyncCadence = Duration(seconds: 5);'),
        reason: 'Round 15 update: sync cadence dropped to 5s (matching '
            'the engine tick) so the notification\'s "Next at" line '
            'refreshes in near-real-time. The `syncSchedules` '
            'fingerprint cache makes this near-free on idle ticks.',
      );
    });

    test(
        'ScheduledOverviewScreen forces an immediate notification re-sync '
        'when opened so the user never sees a stale headline on first '
        'render', () {
      final src =
          _readFile('lib/features/schedule/scheduled_overview_screen.dart');
      expect(
        src,
        contains('required this.onResync,'),
        reason: '_ScheduleBody must accept an onResync callback.',
      );
      expect(
        src,
        contains('widget.onResync()'),
        reason: 'On first frame, the page must call onResync to force '
            'an immediate notification refresh.',
      );
    });
  });

  group('Round 13-D — engine guarantees FG service before each schedule fire',
      () {
    test(
        '_runTick calls coordinator.ensureForegroundForSchedule immediately '
        'BEFORE requestScheduledPlay so a reclaimed FG service can\'t '
        'silently swallow the play', () {
      final src = _readFile('lib/services/scheduler/schedule_engine.dart');
      final tickIdx = src.indexOf('await _coordinator.requestScheduledPlay(');
      expect(tickIdx, greaterThan(0),
          reason: 'requestScheduledPlay call site missing in _runTick.');
      // The 800 chars BEFORE the requestScheduledPlay call must contain
      // the ensureForegroundForSchedule call.
      final region = src.substring(
        (tickIdx - 1500).clamp(0, src.length),
        tickIdx,
      );
      expect(
        region,
        contains('coordinator.ensureForegroundForSchedule'),
        reason: 'The engine must re-enter the foreground binding before '
            'each fire so the OS can\'t silently reclaim the FG service '
            'between ticks and cause the schedule to no-op.',
      );
    });

    test(
        'PlaybackCoordinator.ensureForegroundForSchedule exists and is a '
        'best-effort wrapper around `_audio.enterForeground` (idempotent)', () {
      final src = _readFile('lib/services/playback/playback_coordinator.dart');
      expect(
        src,
        contains('Future<void> ensureForegroundForSchedule()'),
        reason: 'ensureForegroundForSchedule method must be defined.',
      );
      final idx = src.indexOf('Future<void> ensureForegroundForSchedule()');
      final body = src.substring(idx, idx + 800);
      expect(
        body,
        contains('await _audio.enterForeground();'),
        reason: 'The method must invoke enterForeground (which is '
            'idempotent at the handler level).',
      );
    });
  });

  group('Round 13-E — persistent notification uses onlyAlertOnce', () {
    test(
        'The Active ongoing notification sets `onlyAlertOnce: true` so the '
        'periodic 30s re-post never produces a sound or heads-up alert', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      // Find showActiveOngoing's AndroidNotificationDetails block and pin
      // the onlyAlertOnce flag.
      final idx = src.indexOf('Future<void> showActiveOngoing');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 2500);
      expect(
        body,
        contains('onlyAlertOnce: true,'),
        reason: 'Without onlyAlertOnce: true, the 30s engine-driven '
            're-post would peek as a heads-up alert on Samsung One '
            'UI even though the channel has playSound: false.',
      );
    });
  });
}
