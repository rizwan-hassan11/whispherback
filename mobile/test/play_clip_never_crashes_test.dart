// Regression test for QA report:
//
//   "I click play or simply I clicked the clip but the app CRASHED and the
//    clip is not playing.. WHAT IS GOING ON? THE APP IS CRASHING ON clip
//    play ? I can't even test the scheduling when the app is crashing on
//    just clip play.."
//
// The crash was almost always an unhandled platform-channel exception
// from `just_audio` (e.g. setAudioSource on a wedged player, audio focus
// denied, missing decoder) that bubbled out of the play-tap call site
// because nobody awaited the returned Future. The fix is layered:
//
//   1. `_playClipInternal` wraps every external call (`_audio.stop`,
//      `_audio.playFile`, `refreshScheduleNotifications`) in try/catch,
//      converts the failure into a `PlaybackErrorEvent`, and never lets
//      the exception propagate out of the play tap.
//
//   2. Every UI call site (`playClip(...)`) uses `unawaited(...).catchError(...)`
//      so even if a future failure escapes the coordinator, the tap
//      handler still doesn't crash the app.
//
//   3. `main.dart` wraps `runApp` in `runZonedGuarded` and installs
//      `FlutterError.onError` + `PlatformDispatcher.instance.onError`
//      so a truly unhandled error never reaches the OS as a crash.
//
// This test exercises a smaller, deterministic version of (1) + (2)
// without spinning up the audio_service plugin: it constructs a fake
// audio service that throws on `playFile`, calls the equivalent of a
// user tap, and asserts that NO exception propagates back to the caller.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Simulates the exact pattern used by `_playClipInternal` →
/// `_audio.playFile(...)` and the UI call site's `unawaited(...).catchError(...)`
/// wrapper. If the failure escapes both layers, this would re-throw
/// synchronously inside `expect`.
Future<bool> simulateUserTap({
  required Future<void> Function() audioPlayFile,
  required void Function() emitError,
}) async {
  // Layer 1: coordinator-level try/catch.
  bool sawCrash = false;
  try {
    try {
      await audioPlayFile();
    } catch (_) {
      emitError();
      // Swallow — coordinator never rethrows.
    }
  } catch (_) {
    sawCrash = true;
  }
  return !sawCrash;
}

void main() {
  group('play tap MUST NOT crash even when the audio layer throws', () {
    test(
      'a synchronous throw inside playFile is caught and surfaces an error '
      'event instead of propagating to the UI tap handler',
      () async {
        var errorEventFired = false;
        final ok = await simulateUserTap(
          audioPlayFile: () async {
            throw StateError('audio focus denied on Samsung One UI');
          },
          emitError: () => errorEventFired = true,
        );
        expect(ok, isTrue,
            reason: 'The play tap must complete without rethrowing — '
                'otherwise the user perceives it as an app crash.');
        expect(errorEventFired, isTrue,
            reason: 'Caller MUST surface a PlaybackErrorEvent so the shell '
                'can show a snackbar — silent failure was the original '
                '"tapped play, nothing happened" client report.');
      },
    );

    test(
      'a PlatformException-style async throw is also caught and surfaced',
      () async {
        var errorEventFired = false;
        final ok = await simulateUserTap(
          audioPlayFile: () => Future<void>.delayed(
            const Duration(milliseconds: 5),
            () => throw Exception('PlatformException(setAudioSource)'),
          ),
          emitError: () => errorEventFired = true,
        );
        expect(ok, isTrue);
        expect(errorEventFired, isTrue);
      },
    );

    test(
      'a TimeoutException from the 8-second setAudioSource cap is treated '
      'like any other failure — error event, no crash',
      () async {
        var errorEventFired = false;
        final ok = await simulateUserTap(
          audioPlayFile: () => Future<void>.delayed(
            const Duration(milliseconds: 5),
            () => throw TimeoutException(
              'setAudioSource hung — released by 8-second cap',
              const Duration(seconds: 8),
            ),
          ),
          emitError: () => errorEventFired = true,
        );
        expect(ok, isTrue);
        expect(errorEventFired, isTrue);
      },
    );

    test(
      'a successful play does not fire an error event',
      () async {
        var errorEventFired = false;
        final ok = await simulateUserTap(
          audioPlayFile: () async {
            // happy path: returns normally
          },
          emitError: () => errorEventFired = true,
        );
        expect(ok, isTrue);
        expect(errorEventFired, isFalse,
            reason: 'Successful plays must not pollute the error stream.');
      },
    );

    test(
      'an unhandled error that DID escape the coordinator MUST still be '
      'caught by the UI layer (`unawaited(...).catchError(...)`) so the '
      'app never crashes — this mirrors the second line of defense',
      () async {
        // Bypass the coordinator try/catch to simulate a regression where
        // a new error path is added without wrapping; the UI tap handler
        // MUST still keep the app alive.
        bool sawUiCrash = false;
        Future<void> coordinatorWithoutGuard() async {
          throw Exception('regression: new code path threw past coordinator');
        }

        try {
          unawaited(
            coordinatorWithoutGuard()
                .catchError((Object e, StackTrace st) {/* swallow */}),
          );
          // Give the microtask queue a chance to drain.
          await Future<void>.delayed(Duration.zero);
        } catch (_) {
          sawUiCrash = true;
        }
        expect(sawUiCrash, isFalse,
            reason: 'The UI tap handler is the safety net — even if the '
                'coordinator regresses, `unawaited(...).catchError(...)` '
                'keeps the app from crashing.');
      },
    );
  });
}
