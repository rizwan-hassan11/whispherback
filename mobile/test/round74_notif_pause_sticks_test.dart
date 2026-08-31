// Round 74 — notification pause must stick (OEM MediaSession PLAY echo
// was auto-resuming the clip immediately after PAUSE).
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
  group('Round 74 — notification pause sticks', () {
    test('handler.play ignores MediaSession play echo after pause', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('_suppressPlayEchoUntil'));
      expect(handler, contains('_armPlayEchoSuppress()'));
      final pauseIdx = handler.indexOf('Future<void> pause() async');
      final pauseEnd = handler.indexOf('Future<void> seek(', pauseIdx);
      expect(
        handler.substring(pauseIdx, pauseEnd),
        contains('_armPlayEchoSuppress()'),
      );
      final playIdx = handler.indexOf('Future<void> play() async');
      final playEnd = handler.indexOf('Future<void> hideClipMediaNotification(', playIdx);
      final playBody = handler.substring(playIdx, playEnd);
      expect(playBody, contains('_shouldIgnoreMediaSessionPlay'));
      expect(playBody, contains('_appTransportDepth == 0'));
      expect(
        playBody,
        contains('ignored MediaSession play echo after pause'),
      );
    });

    test('ensureAudible never force-plays after pause invalidate', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _ensureAudible(');
      final end = handler.indexOf('Future<void> _playFileBound(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('if (_invalidateForPause || _userPausedClip)'));
      expect(body, contains('await _player.pause()'));
    });

    test('in-app resume clears play-echo suppress', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> resume() async');
      final end = coord.indexOf('Future<void> dismissPlayer()', idx);
      expect(
        coord.substring(idx, end),
        contains('clearPlayEchoSuppress()'),
      );
    });

    test('build id stamped R74', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R78-notif-transport'"));
    });
  });
}
