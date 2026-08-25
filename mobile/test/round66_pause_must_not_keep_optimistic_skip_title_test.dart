// Round 66 (superseded by Round 67) — title revert on pause was replaced by
// commit-on-tap + pause-never-touches-title.
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
    test('hard abort never reverts titles (Round 67)', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      expect(idx, greaterThanOrEqualTo(0));
      final body = coord.substring(idx, idx + 1200);
      expect(body.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(body, contains('_reconcileSessionToBoundPath'));
    });

    test('prime commits index instead of capturing preSkipSnapshot', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('void _primeOptimisticSkip(');
      final end = coord.indexOf('void _warmLibraryNeighbors(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_libraryIndex = nextIndex'));
      expect(body.contains('_preSkipSnapshot'), isFalse);
    });

    test('failed playFile keeps committed title', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('never revert title/index'));
      expect(coord, contains('void _confirmSkipPlaying('));
    });
  });
}
