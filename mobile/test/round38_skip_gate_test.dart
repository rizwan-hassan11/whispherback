// Round 38 — regression test for the QA report:
//
//   Bug 2: "Forward/backward playback controls fail intermittently" —
//   the skip buttons intermittently fail to respond, BOTH inside the
//   app's player and in the system notification bar's media controls.
//   Behavior is inconsistent with no consistent pattern identified.
//
// Root cause: `PlaybackCoordinator._skipPlaylistClip` was called directly
// — with NO mutual exclusion at all — from THREE places:
//   1. `_guardedSkip` (the in-app mini-player / modal skip buttons)
//   2. `onSkipToNextRequested` (the notification bar's media control)
//   3. `onSkipToPreviousRequested` (same, previous direction)
//
// A double-tap, or an in-app tap racing a notification tap (or either
// racing the OTHER direction), sent two concurrent `_player.seek()` /
// `_player.play()` / `_audio.playFile()` calls into the SAME native
// player with nothing serializing them — unlike pause/resume/dismiss,
// which already share `_serializeTransport` for exactly this reason
// (see that gate's doc comment). One of the two concurrent native calls
// would silently lose the race on certain OEMs, matching "sometimes
// works perfectly and sometimes does not respond at all... no
// consistent pattern" on BOTH surfaces (they funnel into the same
// unprotected function).
//
// The fix routes ALL transport through `_serializeTransport` (Round 43).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

/// Mirrors `PlaybackCoordinator._serializeTransport` FIFO semantics.
const Duration kTransportBodyTimeout = Duration(seconds: 12);

class _TransportGate {
  Future<void> _gate = Future<void>.value();

  Future<T> serialize<T>(Future<T> Function() body) {
    final previous = _gate;
    final completer = Completer<T>();
    _gate = previous
        .then((_) => null, onError: (Object _, StackTrace __) => null)
        .then((_) async {
      try {
        final result = await body().timeout(
          kTransportBodyTimeout,
          onTimeout: () => throw TimeoutException(
            'transport gate timeout',
            kTransportBodyTimeout,
          ),
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (kDebugMode) debugPrint('transport gate body failed: $e\n$st');
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

String _read(String relPath) {
  final root = Directory.current.path;
  // Normalize CRLF -> LF so `\n`-anchored substring searches below are not
  // thrown off by the repo's Windows line endings.
  return File(p.join(root, relPath))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
}

void main() {
  group('Round 38 — skip gate mutual exclusion', () {
    test(
        'two concurrent skip calls through the SAME gate are never '
        'in-flight at the same time, regardless of which "surface" '
        'triggered them', () async {
      final gate = _TransportGate();
      var inFlight = 0;
      var maxConcurrent = 0;

      Future<void> nativePlayerCall() async {
        inFlight++;
        maxConcurrent = maxConcurrent > inFlight ? maxConcurrent : inFlight;
        // Simulate the native seek()/play()/setAudioSource() work a real
        // skip does — long enough that, without the gate, a second call
        // fired moments later would clearly overlap it.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight--;
      }

      // Simulates: in-app skipNext tap AND a notification-bar skipNext
      // tap landing almost simultaneously (the exact double-tap /
      // racing-surfaces scenario from the QA report).
      final a = gate.serialize(nativePlayerCall);
      final b = gate.serialize(nativePlayerCall);
      final c = gate.serialize(nativePlayerCall);

      await Future.wait([a, b, c]);

      expect(maxConcurrent, 1,
          reason: 'The whole point of the gate is that the native player '
              'never sees two skip calls in flight at once — if this is '
              '> 1, the race that caused the intermittent failures is '
              'back.');
    });

    test(
        'a hung skip body does not permanently wedge the gate — it times '
        'out and releases so the next tap still works', () async {
      final gate = _TransportGate();

      final hung = gate.serialize<void>(() => Completer<void>().future);

      var followUpRan = false;
      final followUp = gate.serialize<void>(() async {
        followUpRan = true;
      });

      await expectLater(hung, throwsA(isA<TimeoutException>()));
      await followUp;

      expect(followUpRan, isTrue,
          reason: 'One wedged native call must not turn into "the skip '
              'buttons stopped responding entirely" — the gate must '
              'recover, same as the play-gate and pause/resume-gate '
              'already do.');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('Round 38 — production wiring', () {
    test(
        'the in-app skip path AND both notification-bar skip callbacks '
        'all route through `_serializeTransport`', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('Future<T> _serializeTransport<T>('),
          reason:
              'Skip/pause/resume/play must share one FIFO gate (Round 43).');

      // Round 55: `_guardedSkip` queues / debounces; `_runOneSkip` owns the
      // transport body that must still go through `_serializeTransport`.
      expect(src, contains('Future<void> _guardedSkip('));
      final runSkipIdx = src.indexOf('Future<void> _runOneSkip(');
      expect(runSkipIdx, greaterThanOrEqualTo(0));
      final runSkipEnd = src.indexOf(
        '\n  Future<void> _skipPlaylistClip(',
        runSkipIdx,
      );
      final runSkipBody = src.substring(runSkipIdx, runSkipEnd);
      expect(runSkipBody, contains('_serializeTransport('),
          reason: 'The in-app mini-player / modal skip path must go through '
              'the unified transport gate.');

      final initIdx = src.indexOf('Future<void> initialize()');
      expect(initIdx, greaterThanOrEqualTo(0));
      final onNextIdx = src.indexOf('onSkipToNextRequested =', initIdx);
      final onPrevIdx = src.indexOf('onSkipToPreviousRequested =', initIdx);
      expect(onNextIdx, greaterThan(initIdx));
      expect(onPrevIdx, greaterThan(initIdx));
      final wiringSection = src.substring(onNextIdx, onPrevIdx + 120);
      expect(wiringSection, contains('skipNext()'),
          reason: 'Notification skip must funnel into the same skipNext path '
              'as the in-app buttons (which uses _serializeTransport).');
    });
  });
}
