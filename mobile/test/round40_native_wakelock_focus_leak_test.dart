// Round 40 — best-effort fix for the QA report:
//
//   "The scheduled clip plays right on time but sometimes it doesn't
//   play complete — it drops / pauses partway through. Tested 12:00 to
//   18:00 at a 15-minute interval with a ~3:10-3:30 clip: the first
//   5-6 fires cut off around 2:30-2:40, then the next 5-6 played
//   complete, then it cut off again for another 5-6, in repeating
//   blocks."
//
// IMPORTANT — this is NOT a confirmed root cause. A full read of
// WhisperPlaybackService/WhisperAlarmReceiver/WhisperAlarmScheduler and
// the Dart scheduler found no code path that explicitly stops playback
// early; the audio-focus, watchdog, dedup, and native-vs-Dart ownership
// guards from prior rounds all look correct. Without a logcat capture
// from an actual bad streak, the exact trigger (onCompletionListener
// firing early / onErrorListener / a duplicate fire / an OEM process
// kill) cannot be distinguished with certainty.
//
// What THIS round fixes is a real, independently-verifiable resource
// leak that is a plausible contributor to a "batch of failures, then
// fine for a while" pattern: `WhisperPlaybackService.playClip()` runs
// on EVERY scheduled fire, EVERY multi-clip auto-advance, AND (as of
// Round 39) every skip — and each time it called `acquireWakeLock()`
// and `requestAudioFocus()`, both of which allocated a brand-new
// `PowerManager.WakeLock` / `AudioFocusRequest` and overwrote the
// tracked field WITHOUT releasing/abandoning the previous one first.
// Over a 6-hour, 15-minute-interval test that's 24 orphaned partial
// wake locks (each held for up to the 2-hour MAX_PLAYBACK_MS cap) and
// 24 stale AudioFocusRequest objects accumulating. OEM battery
// managers (MIUI, ColorOS, Funtouch, One UI) are well known to run
// periodic batched sweeps that kill/throttle background processes
// holding excessive wake locks — a mechanism that could plausibly
// produce exactly the "bad block, then recovers, then bad again"
// pattern reported, since the process gets reaped and restarts clean
// via the Doze-exempt alarm-clock delivery, degrading again only once
// enough orphaned locks re-accumulate.
//
// This is shipped as a genuine correctness fix (leaking wake locks /
// focus requests is wrong regardless of whether it's THE cause here)
// with the explicit caveat that it may not fully resolve the reported
// symptom — confirming that requires an on-device retest.
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
  group('Round 40 — native wake lock / audio focus leak on every clip', () {
    test('acquireWakeLock releases any previously-held lock before '
        'acquiring a new one', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun acquireWakeLock()');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('\n    }\n', idx);
      final body = src.substring(idx, end);
      expect(body, contains('releaseWakeLock()'),
          reason:
              'Every playClip() call (fresh fire, multi-clip auto-advance, '
              'AND skip) calls acquireWakeLock() again. Without releasing '
              'the previous lock first, each scheduled clip orphans a '
              'held PARTIAL_WAKE_LOCK for up to MAX_PLAYBACK_MS (2h) — '
              'a real leak that accumulates across a multi-hour schedule '
              'test and is a plausible trigger for OEM battery-manager '
              'process kills.');
    });

    test(
        'requestAudioFocus abandons any previously-held request before '
        'requesting a new one', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun requestAudioFocus()');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('\n    }\n', idx);
      final body = src.substring(idx, end);
      expect(body, contains('abandonAudioFocus()'),
          reason:
              'Same leak pattern as the wake lock: every playClip() call '
              'built a new AudioFocusRequest and overwrote the tracked '
              'field without abandoning the previous one, leaving stale '
              'requests accumulating in the system audio focus stack.');
    });
  });
}
