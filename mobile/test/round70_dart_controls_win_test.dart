// Round 70 — sticky MediaSession pause suppress + sticky native ownership
// made BOTH in-app and notification pause/next dead for library playback.
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
  group('Round 70 — Dart controls win', () {
    test('pause echo suppress is time-bounded', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('_suppressPauseEchoUntil'));
      expect(handler, contains('Duration(milliseconds: 450)'));
      expect(handler, contains('_sourceSwapInFlight &&'));
      expect(handler, contains('!_player.playing'));
      expect(
        handler.contains(
            '(_sourceSwapInFlight || suppressMediaSessionPauseEcho)'),
        isFalse,
      );
    });

    test('native ownership never steals a Dart clip session', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('Dart ExoPlayer sessions ALWAYS win'));
      expect(coord, contains('manualPlaying) return false'));
      expect(coord, contains('_audio.isPlayingClip || _audio.currentPath'));
    });

    test('pause is immediate for Dart sessions', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> pause() async');
      final end = coord.indexOf('Future<void> resume() async', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('await _audio.pause()'));
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body, contains('++_transportEpoch'));
      expect(body, contains('return;'));
      expect(body.contains('preempt: native'), isFalse);
      expect(body.contains('_serializeTransport'), isFalse);
    });

    test('notification pause syncs coordinator without re-entering handler.pause', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPause()');
      final end = coord.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body.contains('return pause()'), isFalse);
    });

    test('build id stamped R70', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R79-scheduled-no-autopause'"));
    });
  });
}
