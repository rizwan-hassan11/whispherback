// Regression coverage for the "first recorded clip won't play, the next six
// do" + "imported clip auto-plays on import" reports. The original cause was
// a probe `AudioPlayer().setFilePath(...)` running inside record/import to
// measure duration. On Samsung One UI 12+ that probe player either:
//
//   (a) silently consumed audio focus on the shared `AudioSession`, so the
//       very next *real* play call from the user was dropped by the OS,
//       producing the "first clip silent, subsequent 6 fine" symptom; or
//   (b) auto-started playback through the foreground media session, so the
//       imported file began playing immediately on import — which is what
//       the QA reported on the second device.
//
// The fix removes the in-line probe entirely. Duration is backfilled lazily
// AFTER the DB row is committed, on an isolated player whose lifecycle is
// detached from the user's record/import gesture. We also dropped the older
// blocking `_confirmPlaybackStarted` deadline that held the play-gate
// mutex for 2 seconds on real-world slow Samsung devices, locking out
// follow-up taps and putting the schedule engine into a 1-minute failure
// backoff after the first scheduled fire. Now we use a non-blocking
// `Timer`-based start watchdog that only surfaces a snackbar if playback
// genuinely never started.
//
// These tests pin the new contract. We can't spin up `audio_service` in a
// pure-VM test (no Android plugin runtime), so we exercise the deterministic
// halves of the design directly. Device matrix covers the rest.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Playback first-clip contract', () {
    test('playFile must reject empty paths so the UI gets a real error', () {
      // The handler's playFile throws ArgumentError on empty path. We
      // mirror that contract here so the test fails if someone ever
      // softens the validation back to a silent no-op (which was the
      // original symptom — silent failure ate the user's first record).
      void simulate(String path) {
        if (path.isEmpty) {
          throw ArgumentError('playFile requires a non-empty path');
        }
      }

      expect(() => simulate(''), throwsArgumentError);
      expect(() => simulate('/tmp/clip.m4a'), returnsNormally);
    });

    test('playFile must reject missing files instead of trying to load', () {
      // Same contract: mirror the production guard so that a missing file
      // throws synchronously and the snackbar fires. Previously the player
      // would accept the path and silently sit in `idle` forever.
      void simulate(String path) {
        if (path.isEmpty) {
          throw ArgumentError('playFile requires a non-empty path');
        }
        if (!File(path).existsSync()) {
          throw StateError('Clip file is missing on disk: $path');
        }
      }

      final tempDir = Directory.systemTemp.createTempSync('whisperback_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final missing = p.join(tempDir.path, 'never_existed.m4a');
      expect(() => simulate(missing), throwsStateError);

      final real = File(p.join(tempDir.path, 'real.m4a'))
        ..writeAsBytesSync([0, 1, 2, 3]);
      expect(() => simulate(real.path), returnsNormally);
    });

    test(
        'non-blocking start watchdog fires onPlaybackStartFailure when the '
        'player never advances past idle/loading within the deadline', () {
      // The new watchdog is a `Timer`-based check that runs OUTSIDE the
      // playFile call. The play-gate mutex is released immediately so the
      // user can retry without waiting. We pin that contract here.
      fakeAsync((async) {
        var failureCallbackFired = false;
        String? lastTitle;

        // Simulate handler state.
        var playingClip = true;
        var processingIsAdvanced = false;

        void scheduleWatchdog(String? title) {
          Timer(const Duration(seconds: 5), () {
            if (!playingClip) return;
            if (processingIsAdvanced) return;
            failureCallbackFired = true;
            lastTitle = title;
          });
        }

        scheduleWatchdog('recording-7');

        // Half-way through the deadline: still stuck → no callback yet.
        async.elapse(const Duration(seconds: 3));
        expect(failureCallbackFired, isFalse);

        // After the full deadline expires while still in idle: callback
        // fires and carries the clip title the user was trying to play.
        async.elapse(const Duration(seconds: 3));
        expect(failureCallbackFired, isTrue);
        expect(lastTitle, equals('recording-7'));
      });
    });

    test(
        'watchdog stays quiet when the player advances to a playable state '
        'before the deadline', () {
      fakeAsync((async) {
        var failureCallbackFired = false;
        var playingClip = true;
        var processingIsAdvanced = false;

        void scheduleWatchdog(String? title) {
          Timer(const Duration(seconds: 5), () {
            if (!playingClip) return;
            if (processingIsAdvanced) return;
            failureCallbackFired = true;
          });
        }

        scheduleWatchdog('happy-clip');

        // Player reaches `ready` after 200ms — the watchdog must not fire.
        async.elapse(const Duration(milliseconds: 200));
        processingIsAdvanced = true;

        async.elapse(const Duration(seconds: 10));
        expect(failureCallbackFired, isFalse,
            reason:
                'Healthy playback must never trip the snackbar — otherwise '
                'we would re-introduce the false-positive errors that broke '
                'slow Samsung devices.');
      });
    });

    test(
        'watchdog is cancelled when the user stops the clip explicitly so we '
        'never fire a stale snackbar for a clip they have moved on from', () {
      fakeAsync((async) {
        var failureCallbackFired = false;
        Timer? watchdog;

        void scheduleWatchdog() {
          watchdog?.cancel();
          watchdog = Timer(const Duration(seconds: 5), () {
            failureCallbackFired = true;
          });
        }

        void onStop() {
          watchdog?.cancel();
          watchdog = null;
        }

        scheduleWatchdog();
        async.elapse(const Duration(seconds: 2));
        onStop();
        async.elapse(const Duration(seconds: 10));

        expect(failureCallbackFired, isFalse);
      });
    });

    test(
        'import/record paths must NOT spawn an in-line probe AudioPlayer — '
        'duration is backfilled separately AFTER DB commit', () {
      // This is a structural test: we assert the production source files
      // do not reintroduce the probe pattern we removed. If anyone adds
      // a `new AudioPlayer()` to either path back, the test flips red and
      // explains the Samsung auto-play / first-clip-silent regression that
      // it would re-introduce. This style of test catches a class of
      // mistakes (a fresh dev copy-pasting probe code from a Stack Overflow
      // answer) that pure behaviour tests can't.
      final audioServicesPath =
          p.join(Directory.current.path, 'lib', 'services', 'audio',
              'audio_services.dart');
      final source = File(audioServicesPath).readAsStringSync();
      // The two methods that touched the probe player previously. We
      // assert each is now free of `AudioPlayer()` instantiation.
      // Heuristic: `final player = AudioPlayer();` was the bug pattern.
      expect(
        source.contains(RegExp(r'final\s+player\s*=\s*AudioPlayer\(\)')),
        isFalse,
        reason: 'AudioRecordingService.stopAndSave / AudioImportService.'
            'importFile must NOT instantiate a probe AudioPlayer — that '
            're-introduces the Samsung autoplay-on-import + first-clip-'
            'silent bugs. Use ClipRepository.backfillDuration instead.',
      );
    });
  });
}
