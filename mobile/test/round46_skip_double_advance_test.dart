// Round 46 — single next/prev tap paused audio, reset scrubber to 0:00,
// and often replayed the same clip. Triple-tapping "worked" by racing
// multiple advances.
//
// Causes:
//   1. `_primeOptimisticSkip` advanced the index, then `_skipPlaylistClip`
//      advanced again (2-clip queues wrapped back to the same track).
//   2. Soft skip preemption called `cancelInFlightPlay` → `_player.stop()`,
//      which paused audio and zeroed position on every tap.
//
// Fix: play the primed index (do not advance twice); soft abort only
// invalidates playFile generation without stopping a healthy clip.
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
  group('Round 46 — skip must not double-advance or soft-stop', () {
    test('prime records `_optimisticSkipIndex` and skip consumes it once', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('int? _optimisticSkipIndex'));
      expect(src, contains('_optimisticSkipIndex = target.index'));
      expect(src, contains('final primed = _optimisticSkipIndex'));
      expect(src, contains('_optimisticSkipIndex = null'));

      final skipIdx = src.indexOf('Future<void> _skipPlaylistClip(');
      expect(skipIdx, greaterThanOrEqualTo(0));
      final skipEnd = src.indexOf('\n  Future<void> _playClipAtIndex(', skipIdx);
      final body = src.substring(skipIdx, skipEnd);

      // Must not re-advance from the already-primed library/playlist index
      // with another `(currentIndex + 1) %` before reading `primed`.
      expect(
        body.contains(
            'final nextIndex = next\n          ? (currentIndex + 1)'),
        isFalse,
        reason: 'Re-computing next after prime double-advances the queue.',
      );
      expect(body, contains('final primed = _optimisticSkipIndex'),
          reason: 'Skip body must play the primed target index.');
    });

    test('soft abort invalidates generation without stopping ExoPlayer', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final abortIdx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final abortEnd = coord.indexOf('\n  Future<T> _serializeTransport', abortIdx);
      final abortBody = coord.substring(abortIdx, abortEnd);
      expect(abortBody, contains('_audio.invalidateInFlightPlay()'));
      expect(
        abortBody.contains('await _audio.cancelInFlightPlay()'),
        isTrue,
        reason: 'Hard abort (pause) must still stop in-flight loads.',
      );
      // Soft branch must not stop — only invalidate.
      final softIdx = abortBody.indexOf('} else {');
      expect(softIdx, greaterThanOrEqualTo(0));
      final softBranch = abortBody.substring(softIdx);
      expect(softBranch, contains('invalidateInFlightPlay()'));
      expect(softBranch.contains('cancelInFlightPlay()'), isFalse,
          reason: 'Soft skip abort must not stop() a playing clip.');

      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('void invalidateInFlightPlay()'));
      expect(
        handler,
        contains('/// Invalidates an in-flight [playFile] without stopping'),
      );
    });
  });
}
