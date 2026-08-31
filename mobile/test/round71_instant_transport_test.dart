// Round 71 — instant next/prev title + audio for in-app AND notification;
// pause/resume always work (no post-skip pause-ignore window).
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
  group('Round 71 — instant transport', () {
    test('pending skip primes title/index on the tap frame', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _guardedSkip(');
      final end = coord.indexOf('Future<void> _runOneSkip(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_primeOptimisticSkip(next)'));
      expect(body, contains('invalidateInFlightPlay(forPause: false)'));
      expect(body, contains('alreadyPrimed: true'));
    });

    test('prime publishes notification MediaItem immediately', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_audio.publishPendingClip('));
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('void publishPendingClip('));
      final audio = _read('lib/services/audio/audio_services.dart');
      expect(audio, contains('void publishPendingClip('));
    });

    test('no post-skip pause-ignore window', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord.contains('_ignoreSessionPauseUntil'), isFalse);
      final pause = coord.substring(
        coord.indexOf('Future<void> _handleNotificationPause()'),
        coord.indexOf('Future<void> _handleNotificationPlay()'),
      );
      expect(pause, contains('return pause()'));
      expect(pause.contains('ignored OEM echo'), isFalse);
    });

    test('notification play shares resume()', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final body = coord.substring(
        coord.indexOf('Future<void> _handleNotificationPlay()'),
        coord.indexOf('Future<void> _systemPause()'),
      );
      expect(body, contains('return resume()'));
    });

    test('build id stamped R71', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R76-ocean-pause'"));
    });

    test('Dart ownership and immediate pause still hold', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('Dart ExoPlayer sessions ALWAYS win'));
      final pause = coord.substring(
        coord.indexOf('Future<void> pause() async'),
        coord.indexOf('Future<void> resume() async'),
      );
      expect(pause, contains('invalidateInFlightPlay(forPause: true)'));
      expect(pause, contains('await _audio.pause()'));
      expect(pause.contains('_serializeTransport'), isFalse);
    });
  });
}
