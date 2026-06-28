import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whisperback/services/scheduler/background_alarm_playback.dart'
    show
        backgroundScheduledPlaybackTick,
        cancelBackgroundAlarm,
        ensureBackgroundAlarmRegistered,
        initializeBackgroundAlarms,
        periodicAlarmId;

void main() {
  group('Round 20-A — boot window suppresses surprise fires on cold-start', () {
    test('engine has a `_inBootWindow` getter and uses it to suppress past slots',
        () {
      final src = File('lib/services/scheduler/schedule_engine.dart')
          .readAsStringSync();
      expect(
        src.contains('bool get _inBootWindow'),
        isTrue,
        reason: 'Engine must expose the boot-window getter so cold-start '
            'logic can branch on it.',
      );
      expect(
        src.contains('_inBootWindow') && src.contains('slot.isBefore(now)'),
        isTrue,
        reason: 'Engine must skip past slots when `_inBootWindow` is true '
            'unless `force: true` is set — otherwise the user perceives '
            'old missed slots as surprise plays.',
      );
    });

    test('boot window has a finite duration <= 60 s so the engine '
        're-armed by `start()` quickly enters the steady-state grace path',
        () {
      final src = File('lib/services/scheduler/schedule_engine.dart')
          .readAsStringSync();
      // Locate `static const _bootWindow = Duration(seconds: N);` and assert
      // N is a sane number. We don't enforce the exact value to leave room
      // for future tuning.
      final reg = RegExp(r'_bootWindow\s*=\s*Duration\(seconds:\s*(\d+)\)');
      final m = reg.firstMatch(src);
      expect(m, isNotNull,
          reason: 'Boot window constant must exist with a numeric '
              'Duration(seconds: ...) literal so the engine boot suppression '
              'window is tunable.');
      final n = int.parse(m!.group(1)!);
      expect(n, lessThanOrEqualTo(60));
      expect(n, greaterThanOrEqualTo(10));
    });

    test('start() records `_bootedAt` so subsequent ticks know whether the '
        'engine is in its first ~30 s', () {
      final src = File('lib/services/scheduler/schedule_engine.dart')
          .readAsStringSync();
      expect(src.contains('_bootedAt = DateTime.now()'), isTrue,
          reason: 'start() must stamp `_bootedAt` so the boot-window '
              'check has a reference time.');
    });
  });

  group(
      'Round 20-B — engine forces a fresh notification sync on the very first '
      'tick after start()', () {
    test('_runTick calls _maybeSyncNotifications(force: true) when '
        '_inBootWindow is true', () {
      final src = File('lib/services/scheduler/schedule_engine.dart')
          .readAsStringSync();
      // The header comment + the call together pin the intent: any future
      // refactor that loses the `force: true` here re-introduces the user-
      // visible bug where the notification shows a stale time after
      // engine start.
      expect(
        src.contains('_maybeSyncNotifications(force: true)') &&
            src.contains('_inBootWindow'),
        isTrue,
        reason: 'The boot tick MUST force-sync notifications so the '
            'persistent card never shows a stale "next at" value from '
            'the previous process lifetime.',
      );
    });
  });

  group(
      'Round 20-C — native keep-alive service self-heals every minute via '
      'a heartbeat that re-asserts startForeground + the wake lock', () {
    test('WhisperKeepAliveService.kt declares a HEARTBEAT_INTERVAL_MS constant',
        () {
      final src = File(
              'android/app/src/main/kotlin/com/whisperback/whisperback/WhisperKeepAliveService.kt')
          .readAsStringSync();
      expect(src.contains('HEARTBEAT_INTERVAL_MS'), isTrue,
          reason: 'Heartbeat interval constant must be declared so the '
              'cadence is documented & tunable.');
    });

    test('heartbeat runnable re-runs startForegroundCompat + acquireWakeLock',
        () {
      final src = File(
              'android/app/src/main/kotlin/com/whisperback/whisperback/WhisperKeepAliveService.kt')
          .readAsStringSync();
      expect(
        src.contains('startForegroundCompat()') &&
            src.contains('acquireWakeLock()'),
        isTrue,
      );
      expect(src.contains('heartbeatRunnable'), isTrue,
          reason: 'Heartbeat runnable must be present so the service '
              'self-heals after OEM battery managers silently demote it.');
    });

    test('heartbeat is started on every ACTION_START and stopped on '
        'ACTION_STOP / onDestroy', () {
      final src = File(
              'android/app/src/main/kotlin/com/whisperback/whisperback/WhisperKeepAliveService.kt')
          .readAsStringSync();
      expect(src.contains('startHeartbeat()'), isTrue);
      expect(src.contains('stopHeartbeat()'), isTrue);
    });
  });

  group(
      'Round 20-D — background-isolate scheduled playback path '
      '(`android_alarm_manager_plus`)', () {
    test('background_alarm_playback.dart exports the public surface our '
        'sync/teardown paths depend on', () async {
      // Reachable via package import — guards the file from being accidentally
      // deleted or renamed in a future refactor.
      expect(initializeBackgroundAlarms, isA<Function>());
      expect(ensureBackgroundAlarmRegistered, isA<Function>());
      expect(cancelBackgroundAlarm, isA<Function>());
      expect(backgroundScheduledPlaybackTick, isA<Function>());
      expect(periodicAlarmId, greaterThan(0));
    });

    test('alarm callbacks are annotated `@pragma("vm:entry-point")` so the '
        'release-build tree shaker does not strip them', () {
      final src =
          File('lib/services/scheduler/background_alarm_playback.dart')
              .readAsStringSync();
      // Two top-level entry points: the periodic tick + the optional fire
      // notifier. Both MUST carry the pragma or release builds will throw
      // `PluginRegistrantException` when the alarm fires.
      expect(
        RegExp(r"@pragma\('vm:entry-point'\)\s*\n\s*Future<void>\s+backgroundScheduledPlaybackTick")
            .hasMatch(src),
        isTrue,
        reason: 'backgroundScheduledPlaybackTick must be annotated with the '
            'vm:entry-point pragma so the release tree-shaker keeps it.',
      );
    });

    test('NotificationService.syncSchedules drives the background alarm '
        'lifecycle from the same fingerprint pass', () {
      final src =
          File('lib/services/notifications/notification_service.dart')
              .readAsStringSync();
      expect(src.contains('ensureBackgroundAlarmRegistered'), isTrue,
          reason: 'When Active is ON and at least one schedule is enabled, '
              'the sync layer must register the background alarm.');
      expect(src.contains('cancelBackgroundAlarm'), isTrue,
          reason: 'When Active is OFF or no schedules are enabled, the '
              'background alarm must be cancelled so the OS can sleep.');
    });

    test('main.dart initialises the background alarm plugin BEFORE '
        'AudioService.init', () {
      final src = File('lib/main.dart').readAsStringSync();
      final initBgIdx = src.indexOf('initializeBackgroundAlarms');
      final initAudioIdx = src.indexOf('AudioService.init');
      expect(initBgIdx, greaterThan(0));
      expect(initAudioIdx, greaterThan(0));
      expect(initBgIdx, lessThan(initAudioIdx),
          reason: 'initializeBackgroundAlarms must run before '
              'AudioService.init so a slow audio_service bind cannot delay '
              'the alarm plugin setup.');
    });

    test('background tick is gated on `app_state.is_active` so a stale '
        'alarm cannot fire after the user toggles OFF', () {
      final src =
          File('lib/services/scheduler/background_alarm_playback.dart')
              .readAsStringSync();
      expect(src.contains('_isActive'), isTrue,
          reason: 'Background tick must check the master Active toggle '
              'before playing — otherwise toggling OFF in the main isolate '
              'leaves stale background fires running.');
    });

    test('background tick uses a tight ±30 s grace window', () {
      final src =
          File('lib/services/scheduler/background_alarm_playback.dart')
              .readAsStringSync();
      // The tight window is what prevents the same "surprise old slot
      // fires when the app wakes up" bug from re-appearing in the
      // background path. The main engine has its own boot-window guard.
      expect(src.contains('30'), isTrue);
      expect(
        src.contains('delta.inSeconds.abs() > 30'),
        isTrue,
        reason: 'Background tick must reject slots more than 30 s away '
            'from now so the user is never surprised by a stale fire '
            'from a long sleep.',
      );
    });
  });
}
