// Round 66 — pause during an in-flight next/prev must restore the previous
// title when the new clip has not bound yet. Leaving the optimistic title
// made pause look like it changed the track. Also: playFile returning false
// after ExoPlayer already owns the target path must not wipe that title.
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
  group('Round 66 — pause/skip title integrity', () {
    test('hard abort reverts optimistic title when new path is not bound', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = coord.substring(idx, idx + 1200);
      expect(body, contains('targetPath'));
      expect(body, contains('_revertOptimisticSkipTitle()'));
      expect(body, contains('bound == targetPath'));
    });

    test('preSkipSnapshot is only set when a multi-clip title flips', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('void _primeOptimisticSkip(');
      final end = coord.indexOf('void _warmLibraryNeighbors(', idx);
      final body = coord.substring(idx, end);
      expect(
        body,
        contains('only capture `_preSkipSnapshot` when we actually flip'),
      );
      // Must not assign _preSkipSnapshot at the top before the early returns.
      final firstAssign = body.indexOf('_preSkipSnapshot = _snapshot');
      final libraryEarlyReturn = body.indexOf('_libraryQueue.length <= 1');
      expect(firstAssign, greaterThan(libraryEarlyReturn));
    });

    test('failed playFile still commits when path is already bound', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('bool _isPathBound(String path)'));
      expect(coord, contains('void _commitSkipBindSuccess('));
      expect(
        coord,
        contains('playFile may return false after ExoPlayer already bound'),
      );
    });
  });
}
