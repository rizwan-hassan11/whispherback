// Round 68 (superseded by Round 70) — cancelInFlightPlay on every pause made
// controls worse. Round 70 pauses immediately without stop()-tearing source.
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
  group('Round 68 — pause must not finish the next clip', () {
    test('hard abort no longer cancelInFlightPlay', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final end = coord.indexOf('Future<T> _serializeTransport', idx);
      final body = coord.substring(idx, end);
      expect(body.contains('cancelInFlightPlay'), isFalse);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
    });

    test('manual pause is immediate and invalidates playFile (Round 70)', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('R77-notif-import'));
      final idx = coord.indexOf('Future<void> pause() async');
      final end = coord.indexOf('Future<void> resume() async', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body, contains('await _audio.pause()'));
      expect(body.contains('_serializeTransport'), isFalse);
    });

    test('playFileBound still checks generation before flush', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _playFileBound(');
      final end = handler.indexOf('await _flushPlayerSource();', idx);
      final beforeFlush = handler.substring(idx, end);
      expect(
        beforeFlush.contains('playGen != _playFileGeneration'),
        isTrue,
      );
    });
  });
}
