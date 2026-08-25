// Round 67 — Spotify-like queue ownership.
// Queue index commits on next/prev tap. Title follows index. Pause never
// restores a pre-skip title or queue pointer. That revert/deferred-commit
// machine caused: title changes once, pause changes the clip, then dead controls.
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
  group('Round 67 — commit index on tap; pause never reverts title', () {
    test('prime commits library and playlist indices on tap', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('void _primeOptimisticSkip(');
      final end = coord.indexOf('void _warmLibraryNeighbors(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_libraryIndex = nextIndex'));
      expect(body, contains('_playlistClipIndex = nextIndex'));
      expect(body.contains('_preSkipSnapshot'), isFalse);
      expect(body.contains('Do NOT assign `_libraryIndex` yet'), isFalse);
    });

    test('hard abort never reverts title or queue indices', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final end = coord.indexOf('Future<T> _serializeTransport', idx);
      final body = coord.substring(idx, end);
      expect(body.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(body.contains('_preSkipSnapshot'), isFalse);
      expect(body.contains('_libraryIndex = _preSkipLibraryIndex'), isFalse);
      expect(body, contains('Never touch queue index or title'));
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body, contains('await _audio.pause()'));
    });

    test('skip failure does not restore a pre-skip snapshot', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(coord.contains('PlaybackSnapshot? _preSkipSnapshot'), isFalse);
      expect(coord, contains('never revert title/index'));
      expect(coord, contains('_queueCommittedPath()'));
    });

    test('resume prefers queue-committed path over stale ExoPlayer path', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> resume()');
      final end = coord.indexOf('Future<void> stop() async', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_queueCommittedPath()'));
      expect(body, contains('never a'));
    });

    test('mini-player play icon does not force playing during skip latch', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar.contains('skipPending || snapshot.isPlaying'), isFalse);
      expect(bar, contains('snapshot.isPlaying'));
    });
  });
}
