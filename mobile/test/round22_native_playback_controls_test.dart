// Round 22 — pinning tests for the user-reported QA after Round 21
// shipped:
//
//   1. "Schedule plays with full volume although I set my volume low"
//      → fixed by switching `AudioAttributes.usage` from USAGE_ALARM
//        to USAGE_MEDIA + CONTENT_TYPE_MUSIC, and by routing audio
//        focus through STREAM_MUSIC on legacy paths. Now the user's
//        media volume slider controls scheduled playback exactly like
//        manual playback.
//
//   2. "It does not stop even though I open the app and click the
//      pause/resume in notification bar" / "the mini-player on top of
//      the bottom navbar in the app also do not shows up most of time"
//      → fixed by giving the native FG service explicit pause / resume
//        / stop actions wired to its own MediaStyle notification AND
//        plumbing those into the Dart PlaybackCoordinator over the
//        `com.whisperback.alarms` MethodChannel. The coordinator now
//        promotes a `scheduledPlaying` snapshot when the native
//        listener fires, so the mini-player lights up automatically
//        the moment a scheduled clip starts — including for clips that
//        started while the app was closed (cold-start poll via
//        `getPlaybackState`).
//
// These are source-level guards. The on-device behaviour is exercised
// in the manual QA pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  final path = p.join(root, relPath);
  return File(path).readAsStringSync();
}

void main() {
  group('Round 22 — scheduled-playback volume + controls + mini-player bridge',
      () {
    test(
        'WhisperPlaybackService publishes pause/resume/stop actions in its notification',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('ACTION_PAUSE'),
          reason: 'Notification controls require a PAUSE action constant.');
      expect(src, contains('ACTION_RESUME'),
          reason: 'Notification controls require a RESUME action constant.');
      expect(src, contains('ACTION_STOP_NOW'),
          reason:
              'Notification controls require a STOP action constant so tapping Stop in the shade actually stops the clip.');
      expect(src, contains('MediaStyle'),
          reason:
              'Use MediaStyle so Android renders the actions as music-app-style transport controls (large play/pause button), not generic notification chips.');
      expect(src, contains('servicePendingIntent'),
          reason:
              'Each action needs a unique PendingIntent that re-enters this same service with the correct action extra.');
      expect(src, contains('handlePauseCommand'),
          reason:
              'Pause command must actually pause MediaPlayer and update the notification.');
      expect(src, contains('handleResumeCommand'),
          reason:
              'Resume command must restart MediaPlayer and update the notification.');
    });

    test(
        'WhisperPlaybackService honours a user-set playback volume from SharedPrefs',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('readUserVolume'),
          reason:
              'On every prepare, the service must read the user volume so changing it between clips is honoured.');
      expect(src, contains('mp.setVolume(vol, vol)'),
          reason:
              'The slider value must actually be applied to MediaPlayer; otherwise the prefs write is dead code.');
      expect(src, contains('KEY_VOLUME'),
          reason:
              'Stable preference key for the volume so the bridge and service agree.');
    });

    test(
        'WhisperPlaybackService mirrors state into SharedPrefs + invokes the Dart listener',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('writeState(STATE_PLAYING)'),
          reason:
              'Without writing PLAYING on start the cold-start poll has nothing to read on app launch.');
      expect(src, contains('writeState(STATE_PAUSED)'),
          reason:
              'Pause must persist so a re-launched app shows the mini-player in paused state, not playing.');
      expect(src, contains('writeState(STATE_IDLE)'),
          reason:
              'Idle write on stop / completion clears the cold-start snapshot.');
      expect(src, contains('stateListener'),
          reason:
              'Without a callback, the Dart coordinator only learns about state on the next foreground poll.');
      expect(src, contains('notifyListener'),
          reason: 'Every state transition must hit the listener.');
    });

    test(
        'MainActivity exposes pauseNative / resumeNative / stopNative / setVolume / getPlaybackState',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src, contains('"pauseNative"'),
          reason: 'Dart must be able to pause the native FG service.');
      expect(src, contains('"resumeNative"'),
          reason: 'Dart must be able to resume the native FG service.');
      expect(src, contains('"stopNative"'),
          reason: 'Dart must be able to stop the native FG service.');
      expect(src, contains('"setVolume"'),
          reason:
              'Dart must be able to push the user volume into the prefs the service reads.');
      expect(src, contains('"getPlaybackState"'),
          reason:
              'Dart must be able to poll current state on cold start so the mini-player shows clips that began while the app was killed.');
      expect(src, contains('WhisperPlaybackService.stateListener'),
          reason:
              'The Dart-facing listener must be installed in onCreate, otherwise state callbacks have nowhere to go.');
      expect(src,
          contains('android.os.Handler(android.os.Looper.getMainLooper())'),
          reason:
              'MethodChannel.invokeMethod must be posted to the main thread; the state callback may originate from MediaPlayer\'s worker thread.');
    });

    test('NativeAlarmsBridge exposes the new control + poll APIs', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('pauseNative'),
          reason:
              'Coordinator calls pauseNative on pause when the native source is active.');
      expect(src, contains('resumeNative'),
          reason:
              'Coordinator calls resumeNative on resume when the native source is active.');
      expect(src, contains('stopNative'),
          reason:
              'Coordinator calls stopNative on dismiss / stop when the native source is active.');
      expect(src, contains('setVolume'),
          reason:
              'A future volume slider needs an entry point even if no UI ships in this round.');
      expect(src, contains('fetchPlaybackState'),
          reason:
              'Cold-start poll API must exist for the mini-player to recover a mid-flight scheduled clip.');
      expect(src, contains('stateStream'),
          reason:
              'PlaybackCoordinator subscribes to this stream to drive the mini-player.');
      expect(src, contains('NativePlaybackSnapshot'),
          reason:
              'A typed snapshot is required so coordinator logic isn\'t string-typed.');
    });

    test(
        'PlaybackCoordinator routes pause/resume/dismiss/stop to native when scheduled playback is active',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_nativeScheduledActive'),
          reason:
              'Coordinator must track whether the visible snapshot is a native scheduled clip.');
      expect(src, contains('NativeAlarmsBridge.instance.pauseNative()'),
          reason:
              'Pause tap must reach the native FG service when it owns the clip; otherwise the audio keeps going while the UI claims it paused.');
      expect(src, contains('NativeAlarmsBridge.instance.resumeNative()'),
          reason:
              'Resume tap must reach the native FG service for the same reason.');
      expect(src, contains('NativeAlarmsBridge.instance.stopNative()'),
          reason: 'Stop / dismiss must tear down the native FG service.');
      expect(src, contains('_onNativePlaybackState'),
          reason:
              'Coordinator must observe native transitions so the mini-player can light up on schedule fires.');
      expect(src, contains('AppPlaybackState.scheduledPlaying'),
          reason:
              'Native scheduled playback must promote the snapshot to scheduledPlaying so the existing mini-player visibility check matches.');
    });

    test('app.dart polls native playback state on resume', () {
      final src = _read('lib/app.dart');
      expect(src, contains('NativeAlarmsBridge.instance.fetchPlaybackState'),
          reason:
              'Without a resume poll, the user opens the app mid-fire and the mini-player stays hidden until the next state transition.');
    });

    test('androidx.media is on the classpath so MediaStyle compiles', () {
      final src = _read('android/app/build.gradle.kts');
      expect(src, contains('androidx.media:media'),
          reason:
              'WhisperPlaybackService uses androidx.media.app.NotificationCompat.MediaStyle which requires this dependency to be pinned.');
    });
  });
}
