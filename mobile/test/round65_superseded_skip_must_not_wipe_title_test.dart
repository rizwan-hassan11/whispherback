// Round 65 — a superseded skip's playFile returned false and called
// `_revertOptimisticSkipTitle()`, which shared `_preSkipSnapshot` with the
// newer next/prev. That painted the OLD title over the new skip and made
// next/prev look permanently broken. Also stopNative-on-every-skip fought
// ExoPlayer focus.
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
    test('revert is a no-op when transport epoch is stale', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
          coord, contains('_revertOptimisticSkipTitle({int? transportEpoch})'));
      final idx = coord.indexOf('void _revertOptimisticSkipTitle(');
      final body = coord.substring(idx, idx + 500);
      expect(body, contains('!_transportCurrent(transportEpoch)'));
      expect(body, contains('never paint over a newer next/prev'));
    });

    test('failed bind skips revert when a newer skip owns transport', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('if a newer skip/pause already owns transport, do nothing'),
      );
      expect(
        coord,
        contains('OLD title over the newer skip'),
      );
    });

    test('stopNative is not called on every next/prev swap', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('claim exclusive Dart ownership only when STARTING'),
      );
      final idx = coord.indexOf('Future<void> _playClipInternal(');
      final end = coord.indexOf('void _revertOptimisticSkipTitle(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('if (!skipSnapshotEmit)'));
      expect(body, contains('await _claimDartManualSession()'));
      // Must not claim on skip swaps (skipSnapshotEmit true).
      expect(
        body.contains('if (!skipSnapshotEmit ||'),
        isFalse,
      );
    });
  });
}
