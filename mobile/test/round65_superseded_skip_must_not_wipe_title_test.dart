// Round 65 (superseded by Round 67) — title wipe came from shared revert.
// Round 67 deletes revert entirely and commits index on tap.
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
  group('Round 65 — superseded skip must not wipe newer title', () {
    test('title revert helper is gone (Round 67)', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(coord.contains('PlaybackSnapshot? _preSkipSnapshot'), isFalse);
    });

    test('failed bind does not paint an old title over a newer skip', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('never revert title/index'));
      expect(coord, contains('queue index + title are already committed on tap'));
    });

    test('stopNative is not called on every next/prev swap', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('claim exclusive Dart ownership only when STARTING'),
      );
      final idx = coord.indexOf('Future<void> _playClipInternal(');
      final end = coord.indexOf('void _confirmSkipPlaying(', idx);
      expect(end, greaterThan(idx));
      final body = coord.substring(idx, end);
      expect(body, contains('if (!skipSnapshotEmit)'));
      expect(body, contains('await _claimDartManualSession()'));
      expect(
        body.contains('if (!skipSnapshotEmit ||'),
        isFalse,
      );
    });
  });
}
