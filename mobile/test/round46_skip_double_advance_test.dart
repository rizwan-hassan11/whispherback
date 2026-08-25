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
    test('prime commits index once; skip body does not advance again', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_libraryIndex = nextIndex'));
      expect(src, contains('_playlistClipIndex = nextIndex'));

      final skipIdx = src.indexOf('Future<void> _skipPlaylistClip(');
      expect(skipIdx, greaterThanOrEqualTo(0));
      final skipEnd =
          src.indexOf('\n  Future<void> _playClipAtIndex(', skipIdx);
      final body = src.substring(skipIdx, skipEnd);

      // Must not re-advance from the already-committed library index.
      expect(
        body.contains('((_libraryIndex < 0 ? 0 : _libraryIndex) + 1)'),
        isFalse,
        reason: 'Re-computing next after commit double-advances the queue.',
      );
      expect(body, contains('index was committed on the tap frame'),
          reason: 'Skip body must play the committed queue index.');
    });

    test('soft abort invalidates generation without stopping ExoPlayer', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final abortIdx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final abortEnd =
          coord.indexOf('\n  Future<T> _serializeTransport', abortIdx);
      final abortBody = coord.substring(abortIdx, abortEnd);
      expect(
          abortBody, contains('_audio.invalidateInFlightPlay(forPause: true)'));
      expect(
        abortBody.contains('await _audio.pause()'),
        isTrue,
        reason: 'Hard abort (pause) must still pause ExoPlayer.',
      );
      // Round 69: hard abort must NOT cancelInFlightPlay (that stop()d every pause).
      expect(
        abortBody.contains('await _audio.cancelInFlightPlay()'),
        isFalse,
        reason: 'Hard abort must not stop() the bound clip on pause.',
      );
      // Soft branch must not stop — only invalidate.
      final softIdx = abortBody.lastIndexOf('} else {');
      expect(softIdx, greaterThanOrEqualTo(0));
      final softBranch = abortBody.substring(softIdx);
      expect(softBranch, contains('invalidateInFlightPlay(forPause: false)'));
      expect(softBranch.contains('cancelInFlightPlay()'), isFalse,
          reason: 'Soft skip abort must not stop() a playing clip.');

      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('void invalidateInFlightPlay({bool forPause'));
      expect(
        handler,
        contains('/// Invalidates an in-flight [playFile] without stopping'),
      );
    });
  });
}
