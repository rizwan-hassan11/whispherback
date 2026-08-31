// Round 75 — Spotify-like media notification: sticky pause, dismiss only
// when paused, republish on play, keep session when app is swiped away.
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
  group('Round 75 — Spotify-like notification', () {
    test('user pause latch blocks loading→playing upgrade', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('bool _userPausedClip = false'));
      final idx = handler.indexOf('void _publishClipControls(');
      final body = handler.substring(idx, idx + 800);
      expect(body, contains('!_userPausedClip'));
      expect(body, contains('(playing || loading)'));
    });

    test('broadcastState honors user pause over source-swap latch', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('void _broadcastState(');
      final end = handler.indexOf('static const _stopControl', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('if (_userPausedClip)'));
      expect(
        body.indexOf('if (_userPausedClip)'),
        lessThan(body.indexOf('if (_sourceSwapInFlight)')),
      );
    });

    test('notification deleted: refuse while playing, allow while paused', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> onNotificationDeleted()');
      final end = handler.indexOf('Future<void> skipToNext()', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_notificationDismissed = true'));
      expect(body, contains('await _ensureMediaNotificationVisible()'));
      expect(body, contains('Paused: allow dismiss'));
    });

    test('onTaskRemoved keeps clip MediaSession alive', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> onTaskRemoved()');
      final end = handler.indexOf('Future<void> onNotificationDeleted()', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('if (_playingClip)'));
      expect(body, contains('_ensureMediaNotificationVisible()'));
    });

    test('play echo window is 3.5s and gated on user-pause latch', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('Duration(milliseconds: 3500)'));
      final playIdx = handler.indexOf('Future<void> play() async');
      final playEnd = handler.indexOf('Future<void> hideClipMediaNotification(', playIdx);
      final play = handler.substring(playIdx, playEnd < 0 ? playIdx + 1200 : playEnd);
      expect(play, contains('_userPausedClip'));
      expect(play, contains('_suppressPlayEchoActive'));
    });

    test('build id stamped R76', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R76-ocean-pause'"));
    });
  });
}
