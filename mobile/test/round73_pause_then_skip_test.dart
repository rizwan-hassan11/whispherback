// Round 73 — next/prev pause-then-bind (user-confirmed working path);
// notification pause must honor taps while audio is playing.
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
  group('Round 73 — pause then skip', () {
    test('skip pauses and flushes current clip before bind', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('Future<void> _pauseCurrentBeforeSkip()'));
      expect(coord, contains('await _pauseCurrentBeforeSkip()'));
      expect(coord, contains('await _audio.flushCurrentSource()'));
      final idx = coord.indexOf('Future<void> _runOneSkip(');
      final end = coord.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = coord.substring(idx, end);
      expect(
        body.indexOf('await _pauseCurrentBeforeSkip()'),
        lessThan(body.indexOf('_serializeTransport(')),
      );
    });

    test('handler pause never ignores while player is playing', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> pause() async');
      final end = handler.indexOf('Future<void> seek(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('!_player.playing'));
      expect(body, contains('_sourceSwapInFlight &&'));
      expect(
        body.contains(
          'if (_sourceSwapInFlight &&\n'
          '        suppressMediaSessionPauseEcho &&\n'
          '        _appTransportDepth == 0)',
        ),
        isFalse,
      );
    });

    test('skip does not re-arm pause-echo suppress after bind', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _runOneSkip(');
      final end = coord.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_audio.suppressMediaSessionPauseEcho = false'));
      // Must clear in finally — not leave a post-skip true arm.
      expect(
        body.contains('// Round 71: do NOT arm a post-skip'),
        isFalse,
      );
    });

    test('build id stamped R73', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R73-pause-then-skip'"));
    });
  });
}
