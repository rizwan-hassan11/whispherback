// Round 78 — notification shade pause/resume must work in one tap.
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
  group('Round 78 — notification pause/resume one tap', () {
    test('play gate blocks only echo burst, not settled resume', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('bool get _shouldIgnoreMediaSessionPlay');
      final end = handler.indexOf('/// Runs [action] without firing', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('Duration(milliseconds: 700)'));
      expect(body.contains('_suppressPlayEchoActive'), isFalse);
      expect(body, contains('if (_player.playing) return true'));
    });

    test('ignored play echo does not re-arm suppress window', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final playIdx = handler.indexOf('Future<void> play() async');
      final playEnd =
          handler.indexOf('Future<void> hideClipMediaNotification(', playIdx);
      final play = handler.substring(playIdx, playEnd);
      expect(play.contains('_armPlayEchoSuppress()'), isFalse);
    });

    test('notification pause does not re-enter handler.pause', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPause()');
      final end = coord.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body.contains('return pause()'), isFalse);
      expect(body.contains('await _audio.pause()'), isFalse);
    });

    test('notification play syncs snapshot after handler accepted play', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPlay()');
      final end = coord.indexOf('Future<void> _systemPause()', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_userInitiatedPause = false'));
      expect(body, contains('isUserPausedClip'));
      expect(body, contains('return resume()'));
    });

    test('build id stamped R78', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R79-scheduled-no-autopause'"));
    });
  });
}
