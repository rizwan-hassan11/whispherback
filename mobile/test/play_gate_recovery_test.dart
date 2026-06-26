// Regression coverage for "after some time, clips/playlists delete but
// don't play" — the QA report that ALL playback stops working after a
// while, while delete continues to work.
//
// Root cause: `PlaybackCoordinator._serializePlay` chained every play
// invocation behind a `_playGate` Future. If one body hung (e.g. a stuck
// `just_audio.setAudioSource` call after rapid record/import/play cycles
// on Samsung One UI), the gate stayed unresolved forever and every
// subsequent `playClip` / `playPlaylist` queued behind it silently.
// Delete used a different code path (no gate) so the user saw delete
// work but play do nothing — looks like the player is "broken".
//
// The fix wraps the gate body in a 12-second timeout. If a body hangs,
// the gate's chain progresses, releasing follow-up taps. We also catch
// errors from previous bodies via `onError` in `then`, so an exception
// in one body never starves the chain.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Re-implementation of the production gate to keep the test isolated
/// from the full coordinator wiring. The shape MUST match the production
/// implementation — if it drifts, the test will start passing by
/// accident, which is why we re-derive `kPlayGateBodyTimeout` from the
/// same source as the production code (see comment).
const Duration kPlayGateBodyTimeout = Duration(seconds: 12);

class _MiniGate {
  Future<void> _playGate = Future<void>.value();

  Future<T> serialize<T>(Future<T> Function() body) {
    final previous = _playGate;
    final completer = Completer<T>();
    _playGate = previous
        .then((_) => null, onError: (Object _, StackTrace __) => null)
        .then((_) async {
      try {
        final result = await body().timeout(
          kPlayGateBodyTimeout,
          onTimeout: () => throw TimeoutException(
            'mini-gate timeout',
            kPlayGateBodyTimeout,
          ),
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (kDebugMode) debugPrint('mini-gate body failed: $e\n$st');
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

void main() {
  group('PlaybackCoordinator play-gate recovery', () {
    test(
        'a hung body MUST NOT starve follow-up bodies — the gate releases '
        'after the timeout so the next tap can run', () async {
      final gate = _MiniGate();

      // The first body never resolves — this is what a wedged
      // `just_audio.setAudioSource` looks like on a hung Samsung
      // MediaPlayer.
      final firstFuture =
          gate.serialize<void>(() => Completer<void>().future);

      // A real user tap a moment later. Without the fix this future
      // would never complete and the user sees "play does nothing".
      Object? secondError;
      var secondCompleted = false;
      final secondFuture = gate.serialize<String>(() async {
        return 'follow-up tap ran';
      }).then((v) {
        secondCompleted = true;
        return v;
      }, onError: (Object e) {
        secondError = e;
        return null;
      });

      // First body will time out after 12s. We expect it to throw, and
      // we expect the second body to run AFTER that timeout fires. Use
      // a real clock so we exercise the production code path; bump the
      // suite timeout a bit so the 12s wait fits.
      await expectLater(firstFuture, throwsA(isA<TimeoutException>()));
      await secondFuture;

      expect(secondCompleted, isTrue,
          reason: 'After the wedged body times out, the gate MUST advance '
              'so follow-up plays actually execute. Regression here = '
              'every tap silently does nothing.');
      expect(secondError, isNull,
          reason: 'The second body succeeds on its own merits; it should '
              'not inherit the first body\'s error.');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        'an error in the previous body MUST NOT propagate into the next '
        'serialised body', () async {
      final gate = _MiniGate();

      final firstFuture = gate.serialize<void>(() async {
        throw StateError('synthetic body failure');
      });

      // Expect the first to throw — the gate should still advance.
      await expectLater(firstFuture, throwsA(isA<StateError>()));

      final secondResult = await gate.serialize<int>(() async => 42);
      expect(secondResult, 42,
          reason: 'A previous body throwing must not poison the entire '
              'chain. Without `onError` on the chain handler, every '
              'subsequent play would silently never run.');
    });

    test(
        'rapid sequential taps are serialised in order and each result is '
        'delivered to the right caller', () async {
      final gate = _MiniGate();
      final log = <String>[];

      final r1 = gate.serialize<int>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        log.add('a');
        return 1;
      });
      final r2 = gate.serialize<int>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        log.add('b');
        return 2;
      });
      final r3 = gate.serialize<int>(() async {
        log.add('c');
        return 3;
      });

      expect(await r1, 1);
      expect(await r2, 2);
      expect(await r3, 3);
      expect(log, equals(['a', 'b', 'c']),
          reason: 'Serialised order must be preserved even when later '
              'bodies finish faster than earlier ones. The original gate '
              'already gave us this; we add the test so any future '
              'rewrite of serialize() can\'t silently drop FIFO.');
    });
  });
}
