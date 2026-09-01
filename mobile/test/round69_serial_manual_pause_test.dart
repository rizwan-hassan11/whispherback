// Round 69 (superseded by Round 70) — serial pause behind skip left
// pause dead while skip held the gate. Round 70 pauses Dart sessions
// immediately and invalidates in-flight playFile.
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
  group('Round 69 → 70 — pause must not destroy source via cancelInFlightPlay',
      () {
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

    test('transport build id stamped for QA (Round 70)', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R79-scheduled-no-autopause'"));
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
