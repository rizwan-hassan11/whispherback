// Round 21 — pinning tests for the native alarm-clock scheduled audio
// path. After Round 20 the user reported:
//   1. "Notification bar shows the schedule but nothing is being played
//       in BG when the time comes."
//   2. "App crash popup came when I was using another app and the
//       schedule time came."
//   3. "Notification bar with the schedules becomes hidden sometimes
//       like when the app is opened or clips is playing or when
//       mini-player is working."
//
// Root causes (in order):
//   1. The Round-20 `android_alarm_manager_plus` background isolate
//      could not acquire audio focus on Android 14+ — playing audio
//      from a non-foreground context is silently denied. We've
//      replaced it with a typed `mediaPlayback` foreground service
//      (`WhisperPlaybackService`) started by an exact `setAlarmClock`
//      PendingIntent (`WhisperAlarmReceiver`), which IS the standard
//      alarm-clock architecture.
//   2. The same BG isolate could throw an uncaught
//      `PlatformException` if the DB or audio plugin was momentarily
//      unavailable, which surfaced as the user-visible "WhisperBack
//      keeps stopping" dialog. The receiver+service path wraps every
//      step in try/catch so the OS never sees the crash.
//   3. `notification_sync.dart` was cancelling the persistent
//      schedule card the moment a clip started playing. We now keep
//      both notifications alive (they have different IDs and channels)
//      so the schedule card behaves like a true alarm-clock display.
//
// These tests are SOURCE-LEVEL guards — they pin the architectural
// shape so future refactors can't silently regress to the broken
// Round-20 model. The actual integration is exercised on-device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  final path = p.join(root, relPath);
  return File(path).readAsStringSync();
}

void main() {
  group('Round 21 — native alarm-clock background playback', () {
    test(
        'AndroidManifest declares WhisperAlarmReceiver + WhisperPlaybackService',
        () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('.alarms.WhisperAlarmReceiver'),
          reason:
              'The exact-alarm receiver must be registered so setAlarmClock PendingIntents land.');
      expect(manifest, contains('.alarms.WhisperPlaybackService'),
          reason:
              'The typed mediaPlayback FG service must be declared so it can play audio when started from the background.');
      expect(
          manifest, contains('android:foregroundServiceType="mediaPlayback"'),
          reason:
              'Without foregroundServiceType="mediaPlayback" the OS will deny audio playback on Android 14+.');
      expect(manifest,
          contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'),
          reason: 'mediaPlayback FG type requires this permission.');
      expect(manifest, contains('android.permission.USE_EXACT_ALARM'),
          reason:
              'Android 14+ requires USE_EXACT_ALARM (no runtime grant needed for an alarms app) for setAlarmClock to succeed without user navigation.');
      expect(manifest,
          contains('android.permission.RECEIVE_LOCKED_BOOT_COMPLETED'),
          reason:
              'We re-arm alarms BEFORE the user unlocks the device (essential for morning whispers).');
    });

    test(
        'AndroidManifest registers WhisperBootReceiver with all reboot actions',
        () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('.alarms.WhisperBootReceiver'));
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
      expect(manifest, contains('android.intent.action.LOCKED_BOOT_COMPLETED'));
      expect(manifest, contains('android.intent.action.QUICKBOOT_POWERON'));
      expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    });

    test('android_alarm_manager_plus is removed from pubspec', () {
      final spec = _read('pubspec.yaml');
      expect(spec.contains('android_alarm_manager_plus:'), isFalse,
          reason:
              'Round 21 deletes the Dart background-isolate path; the package must no longer be a dependency.');
    });

    test('background_alarm_playback.dart is removed', () {
      final f = File(p.join(Directory.current.path,
          'lib/services/scheduler/background_alarm_playback.dart'));
      expect(f.existsSync(), isFalse,
          reason:
              'The Round-20 Dart BG isolate file must be deleted to prevent regression to the broken path.');
    });

    test('main.dart no longer calls initializeBackgroundAlarms()', () {
      final src = _read('lib/main.dart');
      expect(src, isNot(contains('initializeBackgroundAlarms')),
          reason:
              'No remaining hook into the deleted android_alarm_manager_plus init path.');
    });

    test('notification_sync keeps schedule card up while a clip plays', () {
      final src = _read('lib/services/notifications/notification_sync.dart');
      // The fix string: the block must NOT cancel the active ongoing on
      // playingClip; it must publish showActiveOngoing whenever active is
      // true, regardless of playingClip.
      expect(
        src,
        contains('Round 21'),
        reason:
            'The fix must reference the round so future refactors know why.',
      );
      // Pin the structural choice: the playingClip-only cancel branch is gone.
      final hasOldCancel = RegExp(
              r'if\s*\(\s*playingClip\s*\)[^{]*\{\s*[^}]*cancelActiveOngoing')
          .hasMatch(src);
      expect(
        hasOldCancel,
        isFalse,
        reason:
            'Round 21: the persistent schedule card must NOT be cancelled when a clip starts; both notifications coexist.',
      );
      expect(src, contains('NativeAlarmsBridge.instance.applySnapshot'),
          reason:
              'syncWhisperNotifications must drive the native alarm-clock scheduler on every refresh.');
    });

    test('NativeAlarmsBridge sends active flag + caps fires per schedule', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains("'active': active"),
          reason:
              'The native side gates playback on the active flag; the bridge must include it on every setSnapshot call.');
      expect(src, contains("_kMaxFiresPerSchedule"),
          reason:
              'A per-schedule fire cap is required to prevent a hyper-active schedule from crowding out the others (Android allows max 500 alarms per app).');
      expect(src, contains("_kMaxFiresTotal"),
          reason: 'A global fire cap is required for the same reason.');
      expect(src, contains("cancelAll"),
          reason:
              'Toggling Active OFF must cancel every pending alarm so the device can stay in Doze.');
    });

    test(
        'WhisperPlaybackService uses mediaPlayback FG type + media (NOT alarm) audio attrs',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK'),
          reason:
              'The service MUST promote to FG with the mediaPlayback type for Android 14+ audio focus.');
      // Round 22 — flipped from USAGE_ALARM → USAGE_MEDIA so scheduled
      // clips follow the user's MEDIA volume (which they actually
      // control via hardware buttons), not the rarely-touched ALARM
      // stream which defaults to 100 %. QA report: "schedule plays at
      // full volume although I set my volume low" was exactly this.
      expect(src, contains('USAGE_MEDIA'),
          reason:
              'Scheduled clips are music, not an alarm tone — they must route through STREAM_MUSIC so the user\'s media volume controls them.');
      expect(src, contains('CONTENT_TYPE_MUSIC'),
          reason:
              'Content type must match the usage for correct OS audio routing.');
      // Only treat NON-comment lines as a violation — the docstring keeps
      // the migration note so future devs know why we flipped away
      // from USAGE_ALARM.
      final codeLines = src
          .split('\n')
          .where((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*'))
          .join('\n');
      expect(codeLines.contains('USAGE_ALARM'), isFalse,
          reason:
              'USAGE_ALARM bypasses the media volume slider; it must NOT appear in any executable code in the scheduled-playback path.');
      expect(src, contains('requestAudioFocus'),
          reason:
              'Without audio focus, the OS silently denies playback in the background.');
      expect(src, contains('PARTIAL_WAKE_LOCK'),
          reason:
              'Without a wake lock, MediaPlayer can pause mid-clip when CPU sleeps.');
      expect(src, contains('isActiveByPrefs'),
          reason:
              'Defense-in-depth: the service must check Active=ON before playing so a stale alarm can never surprise the user after they turned the toggle off.');
    });

    test('WhisperAlarmReceiver enforces 15-minute lateness window', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmReceiver.kt');
      expect(src, contains('15 * 60 * 1000L'),
          reason:
              'Round 33: play late alarms up to 15 minutes (Doze delay) instead of silently dropping at 5 minutes.');
      expect(src, contains('startForegroundService'),
          reason:
              'The receiver must use startForegroundService (Android 8+) so we have the FG-start grant.');
      expect(src, contains('EXTRA_SLOT_EPOCH_MS'),
          reason:
              'Receiver must pass the slot epoch so the service can stamp dedup after MediaPlayer.start.');
      expect(src, contains('WhisperPlaybackService.EXTRA_SLOT_EPOCH_MS'),
          reason: 'Slot epoch must be forwarded on the PLAY_CLIP intent.');
    });

    test('WhisperPlaybackService stamps dedup after MediaPlayer.start', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      expect(src, contains('markFireDeliveredAfterStart'),
          reason:
              'Round 34: dedup stamps only AFTER MediaPlayer.start so a failed prepare can still retry.');
      expect(src, contains('rehydrateFromPrefsIfNeeded'),
          reason:
              'Resume from notification must rehydrate when MediaPlayer was reclaimed.');
    });

    test(
        'WhisperAlarmScheduler prefers setAlarmClock with allowWhileIdle fallback',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmScheduler.kt');
      expect(src, contains('setAlarmClock'),
          reason:
              'setAlarmClock is the highest-reliability alarm class and the only one Doze-exempts.');
      expect(src, contains('syncFromJson'),
          reason:
              'Round 33: diff-sync must exist so setSnapshot never cancelAll mid-delivery.');
      expect(src, contains('CANCEL_GRACE_MS'),
          reason:
              'Round 34: grace window must preserve imminent alarms during realign.');
      expect(src, contains('effectiveStepMs'),
          reason:
              'Round 34: native refill must use Dart step ms, not noisy median.');
      expect(src, contains('setExactAndAllowWhileIdle'),
          reason:
              'If setAlarmClock throws SecurityException we fall back so the user still gets near-on-time alarms.');
      expect(src, contains('FLAG_IMMUTABLE'),
          reason:
              'Android 12+ requires immutable PendingIntents — without this flag setAlarmClock throws on launch.');
    });

    test('MainActivity exposes com.whisperback.alarms MethodChannel', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src, contains('com.whisperback.alarms'),
          reason:
              'The Dart bridge channel name must match the Kotlin handler.');
      expect(src, contains('"setSnapshot"'),
          reason:
              'Dart calls setSnapshot to push the upcoming-fires JSON to native.');
      expect(src, contains('"cancelAll"'),
          reason: 'Dart calls cancelAll on Active OFF.');
      expect(src, contains('WhisperAlarmScheduler.get(applicationContext)'),
          reason: 'The handler must delegate to the native scheduler.');
    });

    test(
        'app.dart bootstrap registers the PlaylistRepository handle for the bridge',
        () {
      final src = _read('lib/app.dart');
      expect(src, contains('registerPlaylistRepositoryForBridge'),
          reason:
              'Without this registration, syncWhisperNotifications has no way to resolve clip paths for the native scheduler and the alarm fires with no clip.');
    });
  });
}
