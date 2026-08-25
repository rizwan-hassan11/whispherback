// Round 69 — manual pause must SERIALIZE behind skip, never hard-preempt
// with cancelInFlightPlay. That stop-on-every-pause was why controls felt
// unchanged across "fixes": every pause destroyed the ExoPlayer source.
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
  group('Round 69 — serial manual pause', () {
    test('manual pause does not hard-preempt', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> pause()');
      final end = coord.indexOf('Future<void> dismissPlayer()', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('Round 69'));
      expect(body, contains('preempt: native'));
      expect(body, contains('revertOptimisticSkip: native'));
      expect(body.contains('preempt: true, revertOptimisticSkip: true'), isFalse);
    });

    test('hard abort does not cancelInFlightPlay', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final end = coord.indexOf('Future<T> _serializeTransport', idx);
      final body = coord.substring(idx, end);
      expect(body.contains('cancelInFlightPlay'), isFalse);
      expect(body.contains('_reconcileSessionToBoundPath'), isFalse);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body, contains('await _audio.pause()'));
    });

    test('transport build id is stamped for QA', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R69-serial-manual-pause'"));
      final settings = _read('lib/features/settings/settings_screen.dart');
      expect(settings, contains('PlaybackCoordinator.transportBuildId'));
    });

    test('resume does not rebind just because paths disagree', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('only rebind when ExoPlayer truly has no source'),
      );
      expect(
        coord.contains('_audio.boundPath != queuePath'),
        isFalse,
      );
    });
  });
}
