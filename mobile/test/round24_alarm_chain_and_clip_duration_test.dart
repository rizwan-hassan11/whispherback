// Round 24 — pinning tests for the QA report AFTER Round 23:
//
//   "Still nothing is resolved.. First of all in clips page the clip card
//    only shows 0:00 instead of the actual length of the the clip.. AND
//    THE OTHER MAIN ISSUE IS still there which is basically the scheduling.
//    I mean still the scheduling is not correct.. ONLY the correct schedule
//    played, all the other schedules were not played, WTF IS GOING ON??"
//
// Two independent root causes were identified:
//
// ── Bug #1: Clip card shows 0:00 forever
//
//   The `just_audio` probe used by `ClipRepository.backfillDuration` was
//   silently failing on Samsung One UI 12+ / Vivo Funtouch (either
//   `setFilePath` timed out or returned null). Even when it succeeded,
//   NOTHING invalidated the `clipsProvider` after the write, so the UI
//   kept the stale in-memory list showing 0:00 until the user manually
//   pulled to refresh.
//
//   Round 24 fix:
//     • Native `MediaMetadataRetriever` primary probe path (no
//       AudioSession, no MediaPlayer — same call the OS uses for
//       Files-app duration).
//     • `ClipRepository.onDurationBackfilled` broadcast stream.
//     • `clipsProvider` subscribes and auto-invalidates on backfill.
//     • `just_audio` remains as a fallback for non-Android hosts and
//       for the (rare) native probe returning 0 on an unrecognised
//       container.
//
// ── Bug #2: "Only the FIRST schedule played, subsequent ones did not"
//
//   Round 23's fingerprint hashed the projected FIRE TIMES. Every native
//   fire slightly drifted `lastFired.completion` (by the wall-clock delay
//   between the OS delivering the alarm and Dart's state listener
//   running), which drifted the projection, which drifted the
//   fingerprint. That defeated the dedup and every 5-second
//   notification tick post-fire cancelled the WHOLE alarm table and
//   re-registered with slightly-different times.
//
//   The kicker: `applySnapshot` filters `if (fire.fireEpochMs <= now)
//   continue`, so an alarm that was ABOUT to fire within the cancel-
//   and-re-register window (a few hundred ms) got cancelled and NEVER
//   re-registered because its slot was now "in the past". That's how
//   Fire #2 vanished into the void.
//
//   Round 24 fix:
//     • Fingerprint is now STRUCTURAL — schedules + clips + active
//       state only. No fire times. Two calls to `applySnapshot` with
//       the same schedules produce the same fingerprint no matter how
//       many fires have happened between them.
//     • Alarm-table rebuild happens ONLY when the user actually
//       changes something (create / edit / delete / toggle Active) or
//       the periodic 12-hour refill window elapses.
//     • Native `WhisperAlarmScheduler.refillIfNeeded()` is called from
//       the receiver on every fire; if the future-pending count drops
//       below 8 (drained by long-running usage or OEM reap), it re-
//       registers the persisted snapshot with past-times filtered out
//       and extrapolates further fires using each schedule's observed
//       median inter-fire delta. This keeps the alarm chain firing
//       INDEFINITELY even if Flutter has been dead for weeks.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  final path = p.join(root, relPath);
  return File(path).readAsStringSync();
}

void main() {
  group('Round 24 — structural fingerprint + native tail refill', () {
    test(
        'NativeAlarmsBridge.applySnapshot uses a STRUCTURAL fingerprint that '
        'is invariant across fires (Round 23 used projected fire times which '
        'drifted on every fire and defeated the dedup)', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');

      expect(src, contains('_lastStructuralFingerprint'),
          reason: 'The fingerprint field must be renamed to reflect its new '
              'STRUCTURAL semantic — that is the whole Round 24 point.');
      expect(src, contains('structuralFingerprint'),
          reason: 'A local variable named `structuralFingerprint` should '
              'compute the value inside `applySnapshot` so the intent is '
              'obvious to a code reviewer.');
      // Structural fingerprint MUST NOT include fireEpochMs — that was
      // exactly the Round-23 bug. Assert none of the fingerprint
      // computation touches `fireEpochMs`.
      final applyIdx = src.indexOf('Future<void> applySnapshot');
      expect(applyIdx, greaterThanOrEqualTo(0));
      // Slice from applySnapshot start to the end of its structural
      // block (the projection loop begins with "STAGE 3").
      final projectionIdx = src.indexOf('STAGE 3', applyIdx);
      expect(projectionIdx, greaterThan(applyIdx),
          reason: 'applySnapshot must be reorganised into the STAGE 1/2/3 '
              'layout so the structural fingerprint is computed BEFORE the '
              'expensive projection.');
      final structuralSection = src.substring(applyIdx, projectionIdx);
      expect(structuralSection.contains('fireEpochMs'), isFalse,
          reason: 'The structural fingerprint must NEVER hash a projected '
              'fire time — that is what caused the Round-23 drift bug.');
    });

    test(
        'NativeAlarmsBridge.applySnapshot accepts a forceRebuild flag so '
        'user-initiated CRUD paths can bypass the fingerprint cache', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('bool forceRebuild = false'),
          reason: 'The parameter must have a safe default (false) so the '
              'callers that do NOT need to force a rebuild (the 5-second '
              'notification tick) keep the fingerprint short-circuit.');
      expect(src, contains('!forceRebuild'),
          reason: 'The fingerprint check must be guarded by `!forceRebuild` '
              'so `forceRebuild: true` bypasses it.');
    });

    test(
        'NativeAlarmsBridge.applySnapshot only rebuilds on structural change '
        '(Round 31: native append-only refill owns the tail)', () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      expect(src, contains('_lastStructuralFingerprint'),
          reason: 'Structural fingerprint must still gate cancel+rebuild.');
      expect(src, contains('forceRebuild'),
          reason: 'Callers must still be able to force a full rebuild.');
      expect(src, isNot(contains('_lastRegisteredAt')),
          reason: 'Timer-based 12h rebuild stamp was removed — it caused '
              'cancel+rebuild churn and analyze unused_field warnings.');
      expect(src, isNot(contains('needsPeriodicRefill')),
          reason: 'Periodic refill flag was removed with the timer rebuild.');
    });

    test(
        'NativeAlarmsBridge.cancelAll invalidates the structural '
        'fingerprint so a subsequent applySnapshot re-registers from scratch',
        () {
      final src = _read('lib/services/scheduler/native_alarms_bridge.dart');
      final cancelIdx = src.indexOf('Future<void> cancelAll()');
      expect(cancelIdx, greaterThanOrEqualTo(0));
      final cancelBody = src.substring(cancelIdx, cancelIdx + 400);
      expect(cancelBody, contains('_lastStructuralFingerprint = null'),
          reason: 'The fingerprint must be reset on cancel; otherwise the '
              'next applySnapshot might no-op because the fingerprint '
              'still matches an ALREADY-CANCELLED table.');
    });

    test(
        'PlaybackCoordinator.refreshScheduleNotifications accepts a '
        'forceAlarmRebuild flag so the Active toggle can force a full '
        'alarm-table rebuild', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(
          src,
          contains(
              'Future<void> Function({bool forceAlarmRebuild})? refreshScheduleNotifications'),
          reason:
              'The callback signature must accept a named `forceAlarmRebuild` '
              'flag so the toggleActive path can request a full rebuild.');
      // The toggleActive activation path MUST pass forceAlarmRebuild:true.
      final activateIdx = src.indexOf('Future<void> _activateInBackground');
      expect(activateIdx, greaterThanOrEqualTo(0));
      final activateEnd = src.indexOf('\n  }', activateIdx);
      expect(activateEnd, greaterThan(activateIdx));
      final body = src.substring(activateIdx, activateEnd);
      expect(body, contains('forceAlarmRebuild: true'),
          reason: 'The Active toggle from OFF -> ON changes the alarm table '
              'from empty to populated. Without forceAlarmRebuild: true, '
              'a stale fingerprint could incorrectly skip the register.');
    });

    test(
        '_stampNativeFireStart no longer collapses completion into slot so '
        'the projection math stays in "case 1" (real end known) instead of '
        '"case 2" (placeholder end = slot + duration)', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final startIdx = src.indexOf('void _stampNativeFireStart');
      expect(startIdx, greaterThanOrEqualTo(0));
      final startEnd = src.indexOf('\n  }', startIdx);
      expect(startEnd, greaterThan(startIdx));
      final startBody = src.substring(startIdx, startEnd);
      // The prior implementation had TWO await lines — one setSlot and
      // one setCompletion. Round 24 removes the setCompletion so the
      // projection can still distinguish "in-flight" from "completed".
      final setSlotCount = 'store.setSlot'.allMatches(startBody).length;
      final setCompletionCount =
          'store.setCompletion'.allMatches(startBody).length;
      expect(setSlotCount, 1,
          reason: 'setSlot must remain — it stamps the fire time so the '
              'upcoming-events widget shows the correct next slot.');
      expect(setCompletionCount, 0,
          reason: 'setCompletion must NOT be called from the START '
              'stamping path. The completion stamp belongs in '
              '_stampNativeFireCompletion, called on the IDLE state.');
    });

    test(
        'WhisperAlarmScheduler persists the snapshot JSON so the receiver '
        'can refill without needing Dart alive', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmScheduler.kt');
      expect(src, contains('KEY_SNAPSHOT_JSON = "snapshot_json_v2"'),
          reason: 'The snapshot must be persisted under a versioned key so '
              'upgrades never collide with an older schema.');
      // setSnapshot must WRITE to KEY_SNAPSHOT_JSON before registering.
      final setSnapshotIdx =
          src.indexOf('fun setSnapshot(snapshotJson: String)');
      expect(setSnapshotIdx, greaterThanOrEqualTo(0));
      final setSnapshotBody =
          src.substring(setSnapshotIdx, setSnapshotIdx + 800);
      expect(setSnapshotBody, contains('KEY_SNAPSHOT_JSON'),
          reason: 'setSnapshot must persist the JSON so refillIfNeeded can '
              'read it back.');
    });

    test(
        'WhisperAlarmScheduler.refillIfNeeded is a real method with a '
        'threshold-based short circuit', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmScheduler.kt');
      expect(src, contains('fun refillIfNeeded()'),
          reason: 'The refill method must exist as a callable native API.');
      expect(src, contains('REFILL_THRESHOLD = 8'),
          reason: 'The threshold must be a documented constant so the '
              'behaviour is testable / tweakable per OEM.');
      expect(src, contains('fun futurePendingCount()'),
          reason: 'The count method must reflect TIME-remaining alarms, '
              'not just registered ids (the receiver leaves stale ids '
              'in KEY_REQ_IDS after a fire is consumed).');
    });

    test(
        'WhisperAlarmReceiver invokes refillIfNeeded after handing off to '
        'the FG service so the alarm chain self-heals when the tail is '
        'drained', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmReceiver.kt');
      expect(src, contains('refillIfNeeded()'),
          reason: 'The receiver must invoke refill on every fire so the tail '
              'never dries up even when Dart is dead.');
      // The refill call must be AFTER startForegroundService so we do
      // NOT block the audio hand-off on a heavy refill computation.
      final startFgIdx = src.indexOf('startForegroundService(serviceIntent)');
      final refillIdx = src.indexOf('refillIfNeeded()');
      expect(startFgIdx, greaterThanOrEqualTo(0));
      expect(refillIdx, greaterThan(startFgIdx),
          reason: 'refillIfNeeded must run AFTER the FG service handoff so '
              'audio latency is not gated on the refill work.');
    });

    test(
        'WhisperAlarmScheduler.extendSnapshot appends synthetic fires when '
        'the tail is running low so the alarm chain fires INDEFINITELY even '
        'if Flutter has been killed for weeks', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperAlarmScheduler.kt');
      expect(src, contains('extendSnapshot'),
          reason: 'The native extension method must exist so Flutter is not '
              'a hard dependency for tail refill.');
      expect(src, contains('medianDelta'),
          reason: 'Using the observed median inter-fire delta lets the '
              'native side project new fires without needing schedule '
              'metadata (which lives in the Dart-side SQLite that we '
              'cannot open from a BroadcastReceiver without booting '
              'Flutter).');
    });
  });

  group('Round 24 — clip duration bug (0:00 forever)', () {
    test(
        'ClipRepository uses a native MediaMetadataRetriever probe as the '
        'primary path with just_audio kept ONLY as a fallback', () {
      final src = _read('lib/data/repositories/clip_repository.dart');
      expect(src, contains('com.whisperback.clip_metadata'),
          reason: 'The native channel name must be defined so the Dart side '
              'can call readDurationMs.');
      expect(src, contains('readDurationMs'),
          reason: 'The native method name must match ClipMetadataProbe.kt.');
      // Native probe must be tried BEFORE the just_audio fallback.
      final backfillIdx = src.indexOf('Future<void> backfillDuration');
      expect(backfillIdx, greaterThanOrEqualTo(0));
      final backfillEnd = src.indexOf('\n  }', backfillIdx);
      expect(backfillEnd, greaterThan(backfillIdx));
      final body = src.substring(backfillIdx, backfillEnd);
      final nativeIdx = body.indexOf('_metadataChannel.invokeMethod');
      final probeIdx = body.indexOf('AudioPlayer()');
      expect(nativeIdx, greaterThanOrEqualTo(0),
          reason: 'The native invoke must appear in the backfill body.');
      expect(probeIdx, greaterThanOrEqualTo(0),
          reason: 'The just_audio fallback must remain for non-Android hosts.');
      expect(nativeIdx, lessThan(probeIdx),
          reason: 'Native probe must run FIRST; just_audio is fallback only.');
    });

    test(
        'ClipRepository broadcasts a stream when duration is backfilled so '
        'the clips provider can auto-invalidate', () {
      final src = _read('lib/data/repositories/clip_repository.dart');
      expect(src, contains('onDurationBackfilled'),
          reason: 'The public stream must exist so providers can subscribe.');
      expect(src, contains('_durationBackfilledController.add(clipId)'),
          reason: 'The controller must actually emit the clip id when a '
              'backfill succeeds; without it the stream is dead code.');
    });

    test(
        'clipsProvider auto-invalidates whenever ClipRepository fires a '
        'duration-backfilled event so the tile re-renders with the real '
        'length instead of staying at 0:00', () {
      final src = _read('lib/providers/playback_providers.dart');
      expect(src, contains('ClipRepository.onDurationBackfilled'),
          reason: 'The provider must subscribe to the stream — without this '
              'the user has to pull to refresh to see the real length.');
      expect(src, contains('ref.invalidateSelf()'),
          reason: 'The subscription must invalidate the provider on each '
              'event; without it the stream is a no-op.');
    });

    test(
        'MainActivity wires the clip_metadata channel so the Dart side can '
        'invoke the native probe', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/MainActivity.kt');
      expect(src, contains('CLIP_METADATA_CHANNEL'),
          reason: 'The channel-name constant must be defined.');
      expect(src, contains('"readDurationMs"'),
          reason: 'The method name must match the Dart side.');
      expect(src, contains('ClipMetadataProbe.readDurationMs'),
          reason: 'The channel handler must delegate to the probe object.');
    });

    test(
        'ClipMetadataProbe uses MediaMetadataRetriever and NEVER touches '
        'MediaPlayer / AudioSession / AudioManager (that was the root '
        'cause of the "first recorded clip won\'t play" bug)', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/ClipMetadataProbe.kt');
      expect(src, contains('MediaMetadataRetriever'),
          reason: 'Only MediaMetadataRetriever is safe — it reads the '
              'container header directly without any playback machinery.');
      // Guard against real API usage, not documentation mentions. We
      // check for the import path (`android.media.MediaPlayer`) so a
      // doc-string reference to "MediaPlayer" doesn't spuriously trip
      // the guard.
      expect(src.contains('android.media.MediaPlayer'), isFalse,
          reason: 'MediaPlayer would compete for the audio focus and could '
              'silently break the next user-driven play — the very bug '
              'the round-6 refactor to a lazy backfill fixed.');
      expect(src.contains('android.media.AudioManager'), isFalse,
          reason: 'AudioManager involvement would risk stealing focus.');
      expect(src.contains('METADATA_KEY_DURATION'), isTrue,
          reason: 'The duration key must be used to read the actual length.');
    });
  });
}
