// Round 55 — QA Aug 23 skip unresponsiveness
//
// Round 54 debounce + _skipInFlight rejected every tap during a multi-second
// flush/playFile swap, and priming ran after flush so the first tap looked dead.
//
// Fix: prime before flush, queue pending skip during in-flight (never drop),
// shorter skip debounce (150ms) vs play/pause (400ms).
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
  group('Round 55 — skip must respond on first tap', () {
    test('optimistic prime runs before flush I/O', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('\n  Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);

      final primeIdx = body.indexOf('_primeOptimisticSkip(next);');
      final flushIdx = body.indexOf('flushCurrentSource');
      expect(primeIdx, greaterThanOrEqualTo(0));
      expect(flushIdx, greaterThan(primeIdx),
          reason:
              'Title must flip before flush so the first tap feels instant.');
    });

    test('in-flight taps queue instead of being discarded', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('bool? _pendingSkipNext'));

      final guardedIdx = src.indexOf('Future<void> _guardedSkip(');
      final guardedEnd =
          src.indexOf('\n  Future<void> _runOneSkip(', guardedIdx);
      final guarded = src.substring(guardedIdx, guardedEnd);

      expect(guarded, contains('if (_skipInFlight)'));
      expect(guarded, contains('_pendingSkipNext = next'));
      expect(guarded, contains('while (_pendingSkipNext != null)'));

      final acceptMethod = src.substring(
        src.indexOf('bool _acceptSkipControl()'),
        src.indexOf('\n  /// Debounces play/pause'),
      );
      expect(acceptMethod.contains('_skipInFlight'), isFalse,
          reason: 'Idle debounce must not block queued in-flight retries.');
    });

    test('skip debounce is shorter than play/pause debounce', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_skipDebounce'));
      expect(src, contains('Duration(milliseconds: 150)'));
      expect(src, contains('_controlDebounce'));
      expect(src, contains('Duration(milliseconds: 400)'));
    });
  });
}
