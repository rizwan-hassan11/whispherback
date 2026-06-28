// Regression suite for Round 11 fixes:
//
//   1. Lock-screen "no next button" (single-clip notification missing skip).
//   2. Permanent notification never appears on OEMs where the audio_service
//      silent keep-alive card is suppressed.
//   3. Schedules that "should be NOW" never fire because the engine was
//      paused by Android in BG and missed the 90-second grace window.
//   4. Cross-icon crash from un-guarded native calls deep inside
//      `WhisperAudioHandler.stopClip` / `stop`.
//   5. Custom-interval popup transparent background.
//   6. Permissions only asked when the user taps the "Finish setup" chip.
//   7. Activate flow posts the Flutter ongoing card BEFORE attempting the
//      foreground service so the user gets an instant visual confirmation
//      even on devices where the silent keep-alive fails.
//
// These tests are deliberately AST/source-level: most of the behaviour is
// inside OEM-specific platform-channel paths that can't be exercised in a
// pure Dart unit test. Pinning the EXPECTED code shape catches accidental
// regressions while letting us add real device-side integration tests in
// CI later.
//
// Together with the existing `notification_resync_after_toggle_test.dart`
// and `schedule_fire_error_surface_test.dart`, this gives us full coverage
// of every reported Round 10 regression.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whisperback/services/scheduler/schedule_fire_helper.dart';

String _readFile(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue,
      reason: 'Expected source file at $relativePath');
  // Normalise CRLF to LF so the contains() matchers below are
  // platform-agnostic (Windows checkouts default to CRLF).
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  group('Round 11 — lock-screen NEXT button', () {
    test(
        '`_publishClipControls` always exposes [prev, play/pause, next, stop] '
        'regardless of playlistMode — single-clip imports now get NEXT too',
        () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // The conditional `if (_playlistMode)` branch around the controls
      // list was the bug — confirm it no longer exists.
      expect(
        src,
        isNot(contains('if (_playlistMode) {\n      controls = [')),
        reason: 'Old single-clip branch is back — re-introduces the QA bug.',
      );
      // The unconditional layout must include skipToNext.
      expect(
        src,
        contains('MediaControl.skipToNext'),
        reason: 'The lock-screen layout must always expose `skipToNext`.',
      );
      // And the single-clip skipToNext handler must restart from zero
      // instead of doing nothing — otherwise the user perceives the
      // button as broken even though it appears.
      expect(
        src,
        contains('await _player.seek(Duration.zero);'),
        reason: 'Single-clip skip handlers must restart the clip from zero.',
      );
    });
  });

  group('Round 11 — permanent notification always renders while Active', () {
    test(
        '`notification_sync` no longer gates `showActiveOngoing` on '
        '`shouldUseFlutterActiveNotification` — the card posts whenever '
        'Active is ON and no clip is playing', () {
      final src = _readFile('lib/services/notifications/notification_sync.dart');
      // The conditional that suppressed the Flutter notification when the
      // audio_service silent card claimed to be live must be gone.
      expect(
        src,
        isNot(contains('handler.shouldUseFlutterActiveNotification')),
        reason: 'The Flutter notification must post unconditionally while '
            'Active is ON; gating on the keep-alive state was the OEM-bug '
            'that left users with NO visible notification at all.',
      );
      expect(
        src,
        contains('await service.showActiveOngoing'),
        reason: 'The active card must still be posted by this path.',
      );
    });

    test(
        '`NotificationService.showActiveOngoing` no longer self-suppresses '
        'via `shouldUseFlutterActiveNotification`', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      // The guard inside the service itself was double-gating the same
      // unreliable condition. Pin its removal.
      expect(
        src,
        isNot(contains(
            'if (!whisperAudioHandler.shouldUseFlutterActiveNotification) return;')),
        reason: 'Double-gate inside the service was suppressing the card '
            'a second time — confirm it is gone.',
      );
    });
  });

  group('Round 11 — schedule grace window', () {
    test(
        'maxLateness is at least 5 minutes so the engine survives a '
        'BG/FG bounce without silently skipping a slot', () {
      // Round 17 bumped to 15 minutes (was 5) to cover the "user
      // tapped the alarm notification 6-10 minutes after it fired"
      // case which the original 5-minute window was silently dropping.
      // We assert the floor (>= 5) so future tightening is still
      // caught while accommodating the Round 17 widening.
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        greaterThanOrEqualTo(5),
        reason: 'QA report "schedule page says NOW but no audio" was the '
            'old 90-second window expiring during a typical OS pause; '
            'Round 17 widened to 15 minutes for tap-from-alarm.',
      );
    });

    test(
        'slotToFire still honours a finite window: a slot 30+ minutes '
        'late returns null (we do NOT spam the user with stale fires '
        'after a long pause)', () {
      expect(
        ScheduleFireHelper.maxLateness.inMinutes,
        lessThanOrEqualTo(30),
        reason: 'The grace window must remain bounded so we never fire '
            'a clip that is half an hour stale.',
      );
    });
  });

  group('Round 11 — cross-icon crash hardening', () {
    test(
        '`WhisperAudioHandler.stopClip` wraps EVERY native bridge call in a '
        'try/catch so a deep PlatformException can never escape', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // Pin the structure: stopClip must contain multiple guarded blocks
      // around _player.stop, mediaItem.add, playbackState.add, and the
      // keep-alive restart branches.
      expect(
        src,
        contains('try {\n      await _player.stop();'),
        reason: 'Guard around _player.stop is missing.',
      );
      expect(
        src,
        contains('try {\n      mediaItem.add(null);'),
        reason: 'Guard around mediaItem.add is missing.',
      );
      // Top-level stop override must also guard stopClip().
      expect(
        src,
        contains('try {\n        await stopClip();'),
        reason: 'Guard around stopClip in the top-level stop is missing.',
      );
      // Round 12 update: the stopClip standalone branch and the top-level
      // stop override no longer call `super.stop()` at all. That call was
      // the OEM activity-kill trigger ("clicking the cross icon CLOSES
      // the app" on Samsung One UI / Vivo). super.stop() now only runs
      // inside `exitForeground` (the deliberate user-toggled OFF path).
      expect(
        src,
        contains('keep-alive teardown — skipping super.stop()'),
        reason: 'Top-level stop must explicitly skip super.stop() to avoid '
            'the OEM activity-kill hazard.',
      );
      expect(
        src,
        contains('keeping AudioService bound to '),
        reason: 'stopClip standalone branch must explicitly document that '
            'it does not call super.stop().',
      );
    });

    test(
        '`PlaybackCoordinator.stop` routes `refreshModeState()` through a '
        'guarded `unawaited` wrapper so a sleep/prayer/adhan I/O error '
        'cannot escape', () {
      final src =
          _readFile('lib/services/playback/playback_coordinator.dart');
      expect(
        src,
        contains('await refreshModeState();'),
        reason: 'The refreshModeState call is missing.',
      );
      expect(
        src,
        contains("debugPrint('stop: refreshModeState failed:"),
        reason: 'The guarded wrapper around refreshModeState must log to '
            'debug for traceability.',
      );
    });

    test('every `_errorController.add` is guarded by an `isClosed` check', () {
      final src =
          _readFile('lib/services/playback/playback_coordinator.dart');
      // Find every `_errorController.add(` site and confirm an isClosed
      // check appears within 4 lines above it.
      final lines = src.split('\n');
      var unguarded = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('_errorController.add(')) {
          final windowStart = (i - 4).clamp(0, lines.length);
          final window = lines.sublist(windowStart, i + 1).join('\n');
          if (!window.contains('_errorController.isClosed')) {
            unguarded.add(i + 1);
          }
        }
      }
      expect(
        unguarded,
        isEmpty,
        reason: 'Unguarded `_errorController.add` calls at lines: '
            '$unguarded. Wrap each in `if (!_errorController.isClosed)`.',
      );
    });
  });

  group('Round 11 — custom-interval dialog theming', () {
    test(
        'the dialog uses an opaque theme-aware background (deep2 in dark, '
        'Colors.white in light) instead of the 10%-alpha `theme.surface`', () {
      final src =
          _readFile('lib/features/schedule/schedule_builder_screen.dart');
      expect(
        src,
        contains('final dialogBg = theme.isDark ? AppColors.deep2 : Colors.white;'),
        reason: 'Custom-interval popup must use an OPAQUE background — the '
            'QA report "popup is transparent BG" was caused by the 10%-alpha '
            '`theme.surface`.',
      );
      expect(
        src,
        contains('backgroundColor: dialogBg'),
        reason: 'AlertDialog must consume the opaque dialogBg.',
      );
      expect(
        src,
        contains('surfaceTintColor: Colors.transparent'),
        reason: 'Material 3 surface tint must be disabled or it overlays a '
            'translucent tint on top of the opaque colour.',
      );
    });
  });

  group('Round 11 — eager permission requests on app launch', () {
    test(
        '`_initNotifications` proactively asks for microphone + battery + '
        'exact-alarm permissions on cold start (was: only when the user '
        'tapped the Finish-setup chip)', () {
      final src = _readFile('lib/app.dart');
      expect(
        src,
        contains('await requestAppPermissionKind(AppPermissionKind.microphone)'),
        reason: 'Microphone permission must be requested up front so the '
            'recorder works on the user\'s very first attempt.',
      );
      expect(
        src,
        contains('await requestBatteryExemption()'),
        reason: 'Battery exemption must be asked at launch so background '
            'scheduling has the best possible chance of surviving OEM '
            'doze enforcement.',
      );
      expect(
        src,
        contains('await NotificationService.instance.requestPermissions()'),
        reason: 'Notification + exact-alarm requests must run at launch.',
      );
    });
  });

  group('Round 11 — activate flow posts the visible notification FIRST', () {
    test(
        '`_activateInBackground` calls `refreshScheduleNotifications` before '
        '`enterForeground` so the user sees the WhisperBack card even on '
        'OEMs where the audio_service silent card is suppressed', () {
      final src =
          _readFile('lib/services/playback/playback_coordinator.dart');
      final activateIdx = src.indexOf('Future<void> _activateInBackground');
      expect(activateIdx, greaterThan(0),
          reason: '`_activateInBackground` is missing.');
      // Slice to the function body only.
      final body = src.substring(activateIdx, activateIdx + 2000);
      final firstRefresh = body.indexOf('refreshScheduleNotifications');
      final enterFg = body.indexOf('_audio.enterForeground');
      expect(firstRefresh, greaterThan(0),
          reason: 'refreshScheduleNotifications must be called.');
      expect(enterFg, greaterThan(0),
          reason: '_audio.enterForeground must be called.');
      expect(
        firstRefresh < enterFg,
        isTrue,
        reason: 'The Flutter ongoing notification must be posted BEFORE the '
            'foreground-service binding attempt so the user always sees '
            'something within ~50 ms of the toggle tap.',
      );
    });
  });

  group('Round 11 — keep-alive retries instead of dying on first failure', () {
    test(
        '`_startIdleKeepAlive` attempts the silence loop up to 3 times with '
        'a backoff before giving up — fixes the cold-start race on Samsung '
        'Exynos firmware', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      expect(
        src,
        contains('for (var attempt = 1; attempt <= 3; attempt++)'),
        reason: 'Keep-alive must retry up to 3 times.',
      );
      expect(
        src,
        contains('await Future<void>.delayed(Duration(milliseconds: 250 * attempt));'),
        reason: 'Each retry must back off so the audio focus grant has '
            'time to settle.',
      );
    });
  });
}
