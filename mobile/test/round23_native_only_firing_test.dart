// Round 23 — pinning tests for the QA report that surfaced AFTER Round 22:
//
//   "There are still lot of issues.. My QA said that the first schedule works
//    good but there are a lot of delays in upcoming schedules and also it
//    stopped working later schedules etc.. WE MUST FIX ALL THE ISSUES.."
//
// The audit traced four compounding root causes:
//
//   1. Dart ScheduleEngine and native WhisperAlarmScheduler both fired the
//      SAME slot, producing overlapping audio streams AND thrashing the
//      alarm-table rebuild mid-fire (drifting subsequent alarms and
//      eventually dropping them). Fix: `_delegateFiringToNative` short-
//      circuits the Dart firing loop on Android — native is authoritative.
//
//   2. Snapshot cap was too low (48 fires per schedule / 180 total). A
//      5-minute schedule covered only ~4 hours; any user who closed the
//      app for longer lost all subsequent fires until they re-opened.
//      Fix: 288 per schedule / 400 total; native MAX_ALARMS bumped from
//      192 to 400 in step.
//
//   3. Native fires never stamped `ScheduleLastFiredStore`, so the
//      Dart projection walked stale data and re-fired slots the native
//      side had already handled. Fix: state listener stamps `setSlot` +
//      `setCompletion` on play, actual completion on idle, AND triggers
//      `refreshScheduleNotifications` so the alarm-table tail is refilled
//      after every fire.
//
//   4. `applySnapshot` was called every 5 seconds by the notification
//      tick and each call cancelled + re-registered 400 alarms, adding
//      measurable AlarmManager binder latency around the actual fire
//      time. Fix: fingerprint the projected fires and no-op when the
//      fingerprint is unchanged.
//
//   Plus a bonus fix — `WhisperAlarmReceiver` de-dupes duplicate deliveries
//   of the same slot within a 60-second window (Vivo / Realme Doze-wake
//   re-delivery bug).
//
// These are source-level guards. On-device behaviour is exercised in the
// manual QA pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  final path = p.join(root, relPath);
  return File(path).readAsStringSync();
}

void main() {
  group(
      'Round 23 — native-only firing + refill on completion + fingerprint dedup',
      () {
    test(
        'ScheduleEngine delegates actual firing to native on Android via '
        '`_delegateFiringToNative` short-circuit', () {
      final src = _read('lib/services/scheduler/schedule_engine.dart');
      expect(src, contains('_delegateFiringToNative'),
          reason:
              'The delegation flag must exist; without it the Dart engine and native scheduler both race to fire the same slot.');
      expect(src, contains('Platform.isAndroid'),
          reason:
              'The default value must auto-detect Android so tests / non-Android hosts keep the old firing path.');
      expect(src, contains('return;'),
          reason:
              'The `_runTick` body must have an early return after the delegation guard.');
      // The guard must come AFTER the notification refresh + heartbeat
      // so those still run, but BEFORE the schedule firing loop.
      final delegateIdx = src.indexOf('if (_delegateFiringToNative)');
      expect(delegateIdx, greaterThanOrEqualTo(0),
          reason:
              'The delegation guard must be a real `if` check inside `_runTick` — not just a doc string.');
      final firingLoopIdx = src.indexOf('for (final schedule in all)');
      expect(firingLoopIdx, greaterThanOrEqualTo(0),
          reason: 'The firing loop must still exist for non-Android hosts.');
      expect(delegateIdx, lessThan(firingLoopIdx),
          reason:
              'The guard must be BEFORE the firing loop; otherwise the loop would run before we short-circuit.');
      final syncIdx = src.indexOf('_maybeSyncNotifications');
      expect(syncIdx, greaterThanOrEqualTo(0),
          reason: 'Notification refresh must still exist.');
      expect(syncIdx, lessThan(delegateIdx),
          reason:
              'Notification refresh must run BEFORE the delegation guard so the persistent card keeps updating even when the Dart firing path is short-circuited.');
    });

    test(
        'ScheduleEngine still refreshes notifications on Android (delegation is FIRE-only)',
        () {
      final src = _read('lib/services/scheduler/schedule_engine.dart');
      expect(src, contains('_maybeSyncNotifications(force: false)'),
          reason:
              'The tick body must still call the notification sync so the persistent card shows a fresh "next at" time even when firing is delegated.');
      expect(src, contains('ensureForegroundForSchedule'),
          reason:
              'The keep-alive heartbeat must still run on Android so the FG service does not get demoted between native fires.');
    });

    test(
        'Snapshot cap bumped from 48/180 to 288/400 so a 5-min schedule '
        'pre-registers a full 24 hours', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('_kMaxFiresPerSchedule = 288'),
          reason:
              'Old value of 48 covered only ~4 hours for a 5-min schedule; the QA "later schedules stopped working" reproduced every time the app was closed for longer than that.');
      expect(src, contains('_kMaxFiresTotal = 400'),
          reason:
              'Total cap must be bumped in step so a single hyper-active schedule can actually reach the new per-schedule cap.');
    });

    test(
        'Native WhisperAlarmScheduler MAX_ALARMS raised from 192 to 400 to '
        'match the Dart cap', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmScheduler.kt');
      expect(src, contains('MAX_ALARMS = 400'),
          reason:
              'Without bumping the native cap, the Dart side would ship 400 fires but the native side would silently drop everything past 192.');
    });

    test(
        'NativeAlarmsBridge.applySnapshot uses a STRUCTURAL fingerprint dedup so the '
        '5-second notification tick does not cancel + re-register 400 alarms '
        '12 times a minute (Round 24 replaces the fire-time fingerprint that '
        'drifted on every fire)', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('_lastStructuralFingerprint'),
          reason: 'Round 24 renamed the fingerprint state so it is clearly '
              'STRUCTURAL (schedules + clips + active) instead of derived '
              'from projected fire times, which drifted on every fire '
              'and defeated the dedup.');
      expect(
          src, contains('structuralFingerprint == _lastStructuralFingerprint'),
          reason: 'The equality check must gate the AlarmManager round-trip; '
              'without it the fingerprint is dead code.');
      // Fingerprint must invalidate on cancelAll, otherwise the next
      // applySnapshot after a cancellation would incorrectly no-op.
      final cancelIdx = src.indexOf('Future<void> cancelAll()');
      expect(cancelIdx, greaterThanOrEqualTo(0));
      final cancelBody = src.substring(cancelIdx, cancelIdx + 500);
      expect(cancelBody, contains('_lastStructuralFingerprint = null'),
          reason:
              'Cancelling all alarms must invalidate the fingerprint so the next applySnapshot re-registers correctly instead of skipping.');
    });

    test(
        'PlaybackCoordinator._onNativePlaybackState stamps ScheduleLastFiredStore '
        'on play + completion so the Dart engine and display advance correctly',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_stampNativeFireStart'),
          reason:
              'Play-time stamp must exist so the Dart engine (if it were still firing) would see the slot as taken.');
      expect(src, contains('_stampNativeFireCompletion'),
          reason:
              'Completion-time stamp must exist so `next = completion + interval` computes correctly.');
      expect(src, contains('ScheduleLastFiredStore.ensureLoaded'),
          reason:
              'The store must be initialised via `ensureLoaded` (not the sync `instance` getter) so an early state callback fired before app bootstrap does not throw.');
      expect(src, contains('store.setSlot(scheduleId, when)'),
          reason:
              'Slot must be stamped so the dedup check in `_slotTakenByOtherSchedule` sees the native fire.');
      // Round 24 — completion is stamped ONLY in `_stampNativeFireCompletion`
      // (fired on IDLE), never in `_stampNativeFireStart`. The old Round-23
      // code mirrored completion=slot on start which collapsed the
      // projection's case-1 (real end known) into case-2 (placeholder end
      // = slot+duration), causing the upcoming-events widget and the
      // `applySnapshot` projection to double-add the playlist duration.
      expect(src, contains('store.setCompletion(scheduleId, when)'),
          reason:
              'Completion must be stamped in `_stampNativeFireCompletion` so the next slot is computed from the actual completion time.');
    });

    test(
        'PlaybackCoordinator triggers refreshScheduleNotifications on idle so '
        'the notification card advances and (in Round 24+) the alarm table '
        'periodic-refill window is respected', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      // Find `_onNativePlaybackState` and check its idle branch includes
      // the refresh call.
      final handlerIdx = src.indexOf('void _onNativePlaybackState');
      expect(handlerIdx, greaterThanOrEqualTo(0));
      final handlerEnd = src.indexOf('\n  }', handlerIdx);
      expect(handlerEnd, greaterThan(handlerIdx));
      final handlerBody = src.substring(handlerIdx, handlerEnd);
      expect(handlerBody, contains('refreshScheduleNotifications?.call()'),
          reason:
              'Without a refresh on completion, the "next in ..." notification '
              'card would stay stuck on the just-fired slot. In Round 24 the '
              'refresh is safe: the underlying `applySnapshot` is guarded by '
              'a structural fingerprint and only touches the alarm table when '
              'the structure or the periodic-refill window (12 h) demands it.');
      expect(handlerBody, contains('_stampNativeFireCompletion'),
          reason:
              'Completion stamp must be inside `_onNativePlaybackState` so the same handler both stamps AND refreshes.');
    });

    test(
        'WhisperAlarmReceiver de-dedupes duplicate deliveries of the same '
        'slot within a 60 s window so Doze-wake re-delivery cannot double-play',
        () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmReceiver.kt');
      expect(src, contains('DEDUP_WINDOW_MS'),
          reason:
              'Window constant must exist so the behaviour is testable / tweakable.');
      expect(src, contains('60_000L'),
          reason:
              '60 s is safely below the 1-min minimum supported interval so genuine successive fires are never mistakenly deduped.');
      expect(src, contains('DEDUP_PREFS'),
          reason: 'Persistent per-app SharedPref file for the dedup ledger.');
      expect(src, contains('whisperback.alarms.dedup'),
          reason:
              'The pref filename must be namespaced so it never collides with other WhisperBack SharedPrefs.');
      expect(src, contains('isDuplicateFire'),
          reason:
              'The dedup helper must be a real method — not a comment — so the receiver actually short-circuits duplicate deliveries.');
      // The dedup check must be inside onReceive.
      final onReceiveIdx = src.indexOf('override fun onReceive');
      expect(onReceiveIdx, greaterThanOrEqualTo(0));
      final onReceiveEnd = src.indexOf('\n    }', onReceiveIdx + 100);
      final onReceiveBody = src.substring(onReceiveIdx, onReceiveEnd);
      expect(onReceiveBody, contains('isDuplicateFire'),
          reason:
              'onReceive must actually call the dedup helper before starting the FG service.');
    });

    test('ScheduleEngine exposes `delegateFiringToNative` for testability', () {
      final src = _read('lib/services/scheduler/schedule_engine.dart');
      expect(src, contains('@visibleForTesting'),
          reason:
              'Tests need to inspect / override the delegation flag; annotate it so lint does not flag internal-only usage.');
      expect(src, contains('bool get delegateFiringToNative'),
          reason: 'Explicit getter so tests can assert the effective value.');
    });

    test(
        'NativeAlarmsBridge.debugResetFingerprint is exposed for test isolation',
        () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('debugResetFingerprint'),
          reason:
              'Tests need to reset the fingerprint between assertions; without this the second call in the same test would incorrectly no-op.');
      expect(src, contains('@visibleForTesting'),
          reason:
              'The reset must be annotated as test-only, not exposed publicly.');
    });
  });
}
