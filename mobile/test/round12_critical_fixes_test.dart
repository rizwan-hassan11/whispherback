// Regression suite for Round 12 fixes. Every test pins a code-level
// invariant that, if broken, brings back a specific QA report verbatim:
//
//   12-A  "When I tap pause and then resume, the mini-player disappears
//          even though the clip is playing." → caused by `resume()`
//          forcing `modalVisible: true`. We assert resume now only
//          flips `isPlaying` and never touches modal visibility.
//
//   12-B  "Tapping the cross icon CLOSES the app instead of pausing
//          and dismissing the mini-player." → caused by
//          `stopClip()` (and the top-level `stop` override) calling
//          `super.stop()` when running outside the keep-alive path.
//          super.stop() tears down the audio_service foreground
//          service, which on Samsung One UI / Vivo / Xiaomi MIUI
//          also kills the host Activity. We assert super.stop() is
//          ONLY called from `exitForeground` now.
//
//   12-C  "Notification interval shown is wrong: 3-minute interval
//          with a 5-minute clip displays the next slot 3 minutes
//          after the current one starts, not 3 minutes after it
//          finishes." → caused by `notification_sync` using
//          `ScheduleFireHelper.upcomingEvents` which clock-grids
//          successive slots. We now compute ONE slot per schedule
//          via `nextFireTime`, which respects the completion stamp.
//
//   12-D  "The status-bar notification icon is just a white circle,
//          not the WhisperBack mark." → caused by
//          `AndroidInitializationSettings('@mipmap/ic_launcher')`
//          (full-colour adaptive launcher) being silhouetted by
//          the system into a featureless blob. We assert the
//          default icon is now the hand-crafted monochrome
//          drawable.
//
//   12-E  "The persistent notification disappears when I open the
//          app and then come back." → caused by some OEMs (Vivo /
//          Xiaomi) dismissing the ongoing card during the activity
//          transition. We assert `_refreshPermissionsAndSync` now
//          re-posts the notification AND schedules a 500 ms
//          re-post as a defensive double-tap.
//
//   12-F  Full-screen-intent permission is requested on cold start
//          so Android 14+ scheduled alarms can auto-launch the
//          activity from screen-off (the only Flutter-only way
//          to play audio at the exact scheduled time without
//          requiring the user to tap a notification).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFile(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue,
      reason: 'Expected source file at $relativePath');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  group('Round 12-A — resume must not force the modal open', () {
    test(
        '`PlaybackCoordinator.resume()` only flips `isPlaying: true` and '
        'does NOT pass `modalVisible: true` (which was hiding the '
        'mini-player after pause+resume cycles)', () {
      final src =
          _readFile('lib/services/playback/playback_coordinator.dart');

      // Find the resume() function body and strip line-comments so the
      // assertion looks only at executable code (documentation lines
      // explaining what we DO NOT do would otherwise trigger the
      // contains() guard).
      final resumeIdx = src.indexOf('Future<void> resume()');
      expect(resumeIdx, greaterThan(0),
          reason: 'resume() method missing.');
      final body = src.substring(resumeIdx, resumeIdx + 1500);
      final codeOnly = body
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        codeOnly,
        isNot(contains('modalVisible: true')),
        reason: 'resume() must not force modalVisible=true in EXECUTABLE '
            'code. QA report "mini-player disappears after pause+resume" '
            'was exactly this — the resume forced the modal open, and '
            'the modal\'s own dismiss then hid both surfaces.',
      );
      expect(
        codeOnly,
        contains('_emit(_snapshot.copyWith(isPlaying: true));'),
        reason: 'resume() must emit ONLY isPlaying: true so modal '
            'visibility is preserved exactly as the user set it.',
      );
    });
  });

  group('Round 12-B — cross icon never closes the app', () {
    test(
        '`WhisperAudioHandler.stopClip` no longer calls `super.stop()` on '
        'the standalone branch (the OEM activity-kill trigger)', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // Find the stopClip body and verify the standalone branch logs
      // its skip and does NOT call super.stop().
      final stopClipIdx = src.indexOf('Future<void> stopClip()');
      expect(stopClipIdx, greaterThan(0),
          reason: 'stopClip() method missing.');
      final standaloneIdx = src.indexOf('if (_standalonePlayback)', stopClipIdx);
      expect(standaloneIdx, greaterThan(0),
          reason: '_standalonePlayback branch missing in stopClip.');
      // The next 1000 chars cover this branch entirely.
      final branchBody = src.substring(standaloneIdx, standaloneIdx + 1200);
      expect(
        branchBody,
        isNot(contains('await super.stop();')),
        reason: 'standalone branch in stopClip must NOT call super.stop()'
            ' — that was the OEM activity-kill bug.',
      );
      expect(
        branchBody,
        contains('keeping AudioService bound'),
        reason: 'standalone branch must explicitly document why it '
            'skips super.stop().',
      );
    });

    test(
        '`WhisperAudioHandler.stop` top-level override also no longer '
        'calls super.stop()', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final stopIdx = src.indexOf('@override\n  Future<void> stop()');
      expect(stopIdx, greaterThan(0),
          reason: 'Top-level stop() override missing.');
      final body = src.substring(stopIdx, stopIdx + 1200);
      expect(
        body,
        isNot(contains('await super.stop();')),
        reason: 'Top-level stop() must NOT call super.stop() — that '
            'was the OEM activity-kill trigger for the cross icon.',
      );
      expect(
        body,
        contains('skipping super.stop()'),
        reason: 'Top-level stop() must explicitly log its skip for '
            'traceability.',
      );
    });

    test(
        '`super.stop()` survives ONLY inside `exitForeground` (the '
        'deliberate user-toggled OFF path)', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      // Count all occurrences of `await super.stop()`. There must be
      // exactly ONE remaining, inside exitForeground().
      final allOccurrences = 'await super.stop();'.allMatches(src).length;
      expect(
        allOccurrences,
        1,
        reason: 'Expected exactly ONE remaining super.stop() call '
            '(inside exitForeground). Found $allOccurrences — '
            'something re-added an OEM activity-kill hazard.',
      );
      // And confirm it's actually inside exitForeground.
      final exitIdx = src.indexOf('Future<void> exitForeground()');
      expect(exitIdx, greaterThan(0));
      final exitBody = src.substring(exitIdx, exitIdx + 2000);
      expect(
        exitBody,
        contains('await super.stop();'),
        reason: 'super.stop() must remain in exitForeground to cleanly '
            'tear down the FG service on the deliberate OFF path.',
      );
    });
  });

  group('Round 12-C — notification interval respects playlist duration', () {
    test(
        'notification_sync.dart computes upcoming slots per schedule via '
        '`nextFireTime`, not a clock-grid of N successive slots', () {
      final src =
          _readFile('lib/services/notifications/notification_sync.dart');
      expect(
        src,
        isNot(contains('ScheduleFireHelper.upcomingEvents(')),
        reason: 'upcomingEvents is the clock-grid path that ignored '
            'playlist duration. notification_sync must compute its '
            'upcoming events from `nextFireTime` instead so the '
            'completion stamp (= playlist end + interval) drives '
            'the displayed next-slot time.',
      );
      expect(
        src,
        contains('ScheduleFireHelper.nextFireTime('),
        reason: 'notification_sync must call nextFireTime so the '
            'completion-stamped interval-from-end semantics apply.',
      );
      // Round 14 split lastFired into slot + completion so the helper
      // can do real interval-from-end math. Both must be passed.
      expect(
        src,
        contains('lastFired.slot('),
        reason: 'sync must read the slot stamp so still-firing rounds '
            'project end correctly.',
      );
      expect(
        src,
        contains('lastFired.completion('),
        reason: 'sync must read the completion stamp so the next slot '
            'is interval-from-end.',
      );
      expect(
        src,
        contains('forDisplay: true'),
        reason: 'sync must request display-only mode so past slots in '
            'the engine grace window never leak into the notification.',
      );
    });
  });

  group('Round 12-D — notification icon is the WhisperBack silhouette', () {
    test(
        'AndroidInitializationSettings default icon is `ic_notification` '
        '(monochrome silhouette), not `@mipmap/ic_launcher` (full-colour '
        'launcher that gets silhouetted to a white circle)', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains("AndroidInitializationSettings('ic_notification')"),
        reason: 'Default notification icon must be the monochrome '
            'silhouette drawable.',
      );
      expect(
        src,
        isNot(contains("AndroidInitializationSettings('@mipmap/ic_launcher')")),
        reason: 'The full-colour launcher icon being used as the '
            'notification small-icon was the QA report "notification '
            'icon is just a white circle".',
      );
      // The active-ongoing notification must also explicitly pin the icon
      // and color so OEMs that ignore the channel default still render
      // the silhouette + brand tint.
      expect(
        src,
        contains("icon: 'ic_notification',"),
        reason: 'Active ongoing notification must explicitly pin the '
            'silhouette icon (some OEMs ignore channel defaults).',
      );
      expect(
        src,
        contains('color: const Color(0xFF2E8BFF),'),
        reason: 'Brand accent colour must be pinned so the silhouette '
            'reads as WhisperBack blue, not the system default.',
      );
    });

    test('the monochrome notification drawable exists at the expected path',
        () {
      final file =
          File('android/app/src/main/res/drawable/ic_notification.xml');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'ic_notification.xml drawable is missing — Android will '
            'fall back to a featureless white square.',
      );
      final content = file.readAsStringSync();
      expect(
        content,
        contains('fillColor="#FFFFFFFF"'),
        reason: 'Notification icon paths must be solid white — Android '
            'discards baked-in colours.',
      );
    });
  });

  group('Round 12-E — persistent notification re-posts on resume', () {
    test(
        '`_refreshPermissionsAndSync` re-syncs the notification IMMEDIATELY '
        'and then again 500 ms later as a defensive double-tap', () {
      final src = _readFile('lib/app.dart');
      // Find the function body and verify the double-call shape.
      final idx = src.indexOf('Future<void> _refreshPermissionsAndSync()');
      expect(idx, greaterThan(0),
          reason: '_refreshPermissionsAndSync method missing.');
      final body = src.substring(idx, idx + 2500);
      // Must contain at least two `await syncWhisperNotifications(`
      // calls inside this method.
      final calls = 'await syncWhisperNotifications('.allMatches(body).length;
      expect(
        calls,
        greaterThanOrEqualTo(2),
        reason: '_refreshPermissionsAndSync must call '
            'syncWhisperNotifications at least twice (immediate + '
            'delayed re-post) to defeat OEM dismissal during the '
            'activity transition.',
      );
      expect(
        body,
        contains('Duration(milliseconds: 500)'),
        reason: 'The delayed re-post must use a 500 ms delay so it '
            'lands AFTER the OS settles the activity transition.',
      );
    });
  });

  group('Round 12-F — full-screen-intent permission requested at launch', () {
    test(
        '`NotificationService.requestPermissions` asks for '
        '`requestFullScreenIntentPermission` so Android 14+ scheduled '
        'alarms can auto-launch the activity from screen-off', () {
      final src =
          _readFile('lib/services/notifications/notification_service.dart');
      expect(
        src,
        contains('await android?.requestFullScreenIntentPermission();'),
        reason: 'Full-screen-intent permission must be requested. '
            'Without it, scheduled alarms on Android 14+ only post a '
            'notification and the user has to tap it manually — '
            'breaking the "audio plays at scheduled time" promise.',
      );
    });

    test(
        '`exitForeground` clears `_keepAliveRunning` along with '
        '`_keepAlive` so a subsequent re-enter does not skip the '
        'silence-loop restart', () {
      final src = _readFile('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> exitForeground()');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 1500);
      expect(
        body,
        contains('_keepAliveRunning = false;'),
        reason: 'exitForeground must clear the running flag too so the '
            'next enterForeground actually attempts the silence loop '
            'instead of short-circuiting on the cached truthy state.',
      );
    });
  });
}
