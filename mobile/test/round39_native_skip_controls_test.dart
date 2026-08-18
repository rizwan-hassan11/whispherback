// Round 39 — regression test for the QA report:
//
//   "In playlist we have 2 buttons for play next and play previous
//   audio. It isn't working, I pressed it lots of times, it didn't
//   play the next or previous audio. Must be fixed in the notification
//   bar too."
//
// Root cause: when a schedule fires on Android, the audio is played by
// the NATIVE `WhisperPlaybackService` (a raw `android.media.MediaPlayer`
// foreground service), not the Dart-side `just_audio` player. Every
// other transport control (pause/resume/stop/dismiss) already had a
// `_nativeOwnsPlayback` branch in `PlaybackCoordinator` that routes the
// request over the `com.whisperback.alarms` MethodChannel to the native
// service — see Round 22. `skipNext`/`skipPrevious` never got the same
// treatment: `_skipPlaylistClip` always fell into the just_audio /
// library-queue path, which either no-op'd (no Dart `playlistId` set
// for a native fire) or started a SECOND, competing `just_audio` stream
// on top of the still-audible native clip.
//
// Separately, `WhisperPlaybackService`'s own notification (used while a
// schedule is playing) never had skip actions at all — only
// Pause/Resume/Stop — so there was no way to skip from the shade/lock
// screen during a scheduled play in the first place.
//
// The fix:
//   1. `WhisperPlaybackService` gains `ACTION_SKIP_NEXT` /
//      `ACTION_SKIP_PREVIOUS`, a `handleSkipCommand` that moves its own
//      `clipQueueIndex` and replays, and notification actions wired to
//      those actions.
//   2. `MainActivity` exposes a `skipNative` MethodChannel entry that
//      forwards to the service.
//   3. `NativeAlarmsBridge` exposes `skipNative({required bool next})`.
//   4. `PlaybackCoordinator._skipPlaylistClip` checks
//      `_nativeOwnsPlayback` first, exactly like `pause()` does, and
//      routes to `NativeAlarmsBridge.instance.skipNative` instead of
//      falling into the just_audio path.
//
// These are source-level guards for the native Kotlin half (no JVM test
// harness in this repo — see Round 22's test for the same pattern). The
// on-device behaviour is exercised in the manual QA pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
}

void main() {
  group('Round 39 — native scheduled-playback skip controls', () {
    test(
        'WhisperPlaybackService defines skip actions and a handler that '
        'moves its own clip queue', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('ACTION_SKIP_NEXT'),
          reason: 'A distinct action constant is required so the '
              'notification / MethodChannel can request a forward skip.');
      expect(src, contains('ACTION_SKIP_PREVIOUS'),
          reason: 'A distinct action constant is required so the '
              'notification / MethodChannel can request a backward skip.');
      expect(src, contains('handleSkipCommand'),
          reason: 'Skip must be handled by moving clipQueueIndex and '
              'replaying — there is no other hook that can move the '
              'native queue on demand (only onCompletionListener does, '
              'and only forward, only on natural completion).');

      final onStartIdx = src.indexOf('override fun onStartCommand(');
      expect(onStartIdx, greaterThanOrEqualTo(0));
      final onStartEnd = src.indexOf('\n    }\n', onStartIdx);
      final onStartBody = src.substring(onStartIdx, onStartEnd);
      expect(onStartBody, contains('ACTION_SKIP_NEXT ->'),
          reason:
              'onStartCommand must dispatch ACTION_SKIP_NEXT to the handler.');
      expect(onStartBody, contains('ACTION_SKIP_PREVIOUS ->'),
          reason: 'onStartCommand must dispatch ACTION_SKIP_PREVIOUS to '
              'the handler.');

      final handleSkipIdx = src.indexOf('private fun handleSkipCommand(');
      expect(handleSkipIdx, greaterThanOrEqualTo(0));
      final handleSkipEnd = src.indexOf('\n    }\n', handleSkipIdx);
      final handleSkipBody = src.substring(handleSkipIdx, handleSkipEnd);
      expect(handleSkipBody, contains('clipQueueIndex'),
          reason: 'The handler must move the native clip-queue index, '
              'the same state onCompletionListener auto-advances.');
      expect(handleSkipBody, contains('playClipAfterUiUpdate('),
          reason: 'After moving the index the handler must actually '
              'start the newly-targeted clip. The start is posted so '
              'Flutter is notified before MediaPlayer.setDataSource.');
      expect(handleSkipBody, contains('notifyListener(STATE_PLAYING)'),
          reason: 'Skip must push the new title/playing state to Flutter '
              'before prepareAsync, otherwise next/prev feels laggy.');
    });

    test(
        'WhisperPlaybackService notification exposes skip actions '
        '(so the notification bar / lock screen can skip too)', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final buildNotifIdx = src.indexOf('private fun buildNotification(');
      expect(buildNotifIdx, greaterThanOrEqualTo(0));
      final buildNotifEnd = src.indexOf('\n    }\n', buildNotifIdx);
      final buildNotifBody = src.substring(buildNotifIdx, buildNotifEnd);
      expect(buildNotifBody, contains('ACTION_SKIP_PREVIOUS'),
          reason:
              'The notification must post a PendingIntent for skip-previous.');
      expect(buildNotifBody, contains('ACTION_SKIP_NEXT'),
          reason: 'The notification must post a PendingIntent for skip-next.');
      expect(buildNotifBody, contains('setShowActionsInCompactView(0, 1, 2)'),
          reason: 'Compact view must show prev / play-pause / next — '
              'the standard transport layout — not just the two it had '
              'before (which is now indices 1 and 3 with skip actions '
              'inserted around them).');
    });

    test('MainActivity exposes a skipNative MethodChannel entry', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src, contains('"skipNative"'),
          reason: 'Dart must be able to ask the native FG service to '
              'skip forward/back.');
      expect(src, contains('WhisperPlaybackService.ACTION_SKIP_NEXT'),
          reason:
              'skipNative must forward to the service\'s skip-next action.');
      expect(src, contains('WhisperPlaybackService.ACTION_SKIP_PREVIOUS'),
          reason: 'skipNative must forward to the service\'s '
              'skip-previous action.');
    });

    test('NativeAlarmsBridge exposes skipNative', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('Future<void> skipNative({required bool next})'),
          reason:
              'Coordinator calls skipNative when the native source is active.');
      expect(src, contains("'skipNative'"),
          reason: 'Must invoke the same method name MainActivity handles.');
    });

    test(
        'PlaybackCoordinator routes skipNext/skipPrevious to native when '
        'scheduled playback is native-owned', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final skipIdx = src.indexOf('Future<void> _skipPlaylistClip(');
      expect(skipIdx, greaterThanOrEqualTo(0));
      final skipEnd = src.indexOf('\n  }\n', skipIdx);
      final skipBody = src.substring(skipIdx, skipEnd);
      expect(skipBody, contains('_nativeOwnsPlayback'),
          reason: 'Without this check, a skip tap during a native '
              'scheduled play falls through to the just_audio / '
              'library-queue path below, which has no idea a native '
              'clip is even playing — the exact reported bug.');
      expect(skipBody, contains('NativeAlarmsBridge.instance.skipNative('),
          reason: 'When native owns playback, the skip must reach the '
              'native FG service the same way pause/resume/stop already '
              'do.');
      // The native branch must come before the just_audio playlistId
      // lookup, otherwise it is dead code.
      final nativeBranchIdx = skipBody.indexOf('_nativeOwnsPlayback');
      final playlistLookupIdx = skipBody.indexOf('_snapshot.playlistId');
      expect(nativeBranchIdx, lessThan(playlistLookupIdx),
          reason:
              'The native check must short-circuit before the just_audio path.');
    });
  });
}
