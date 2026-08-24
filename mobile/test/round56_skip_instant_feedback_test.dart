// Round 56 — QA Aug 23 skip still felt dead after Round 55
//
// Causes:
//   1. Mini-player prefers MediaItem over snapshot (Round 51) — optimistic
//      skip primed snapshot only, so title/icon stayed stale until bind.
//   2. Coordinator flushCurrentSource + handler flush doubled I/O latency.
//   3. Skip debounce + in-flight reject dropped retry taps.
//
// Fix: skipTransportActive → snapshot wins in mini-player; one flush in
// handler; queue in-flight taps; preload playlist cache before prime.
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
  group('Round 56 — skip instant feedback', () {
    test('_runOneSkip preloads cache and does not double-flush', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(');
      final end = src.indexOf('\n  Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('await _ensurePlaylistCache'));
      expect(body, contains('_primeOptimisticSkip(next)'));
      expect(body.contains('flushCurrentSource'), isFalse);
      final primeIdx = body.indexOf('_primeOptimisticSkip(next)');
      final transportIdx = body.indexOf('_serializeTransport');
      expect(primeIdx, lessThan(transportIdx));
    });

    test('mini-player title follows bound MediaItem (not optimistic snapshot)',
        () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('skipTransportActive'));
      expect(bar, contains('skipPending && snapTitle'));
      expect(bar, contains('skipPending ? true : mediaSessionPlaying'));
    });

    test('in-flight skip taps queue instead of debounce-reject', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('bool get skipTransportActive'));
      expect(src.contains('_acceptSkipControl'), isFalse);
      final guardedIdx = src.indexOf('Future<void> _guardedSkip(');
      final guardedEnd =
          src.indexOf('\n  Future<void> _runOneSkip(', guardedIdx);
      final guarded = src.substring(guardedIdx, guardedEnd);
      expect(guarded, contains('_pendingSkipNext = next'));
      expect(guarded, contains('while (_pendingSkipNext != null)'));
    });
  });
}
