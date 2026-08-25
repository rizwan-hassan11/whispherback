// Round 61 — Round 60 wiped the Spotify bar + notification.
//
// Cause: playFile refused to publish MediaItem until `_player.playing` was
// true within ~1.5s. On OEM devices the playing flag lags (buffering), so
// MediaItem never published → playFile returned false → playClip called
// stop() → activeIdle with no titles → no mini-player, no notification,
// next/prev dead.
//
// Production players (Spotify / audio_service):
//   1. setAudioSource
//   2. publish MediaItem immediately (notification + bar stay alive)
//   3. play() hard, suppress MediaSession pause-echo during the window
//   4. never stop() the session just because playing lagged
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
  group('Round 61 — session stays alive; skip becomes audible', () {
    test('playFile publishes MediaItem as soon as the source is bound', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _playFileBound(');
      final end = handler.indexOf('Timer? _startWatchdog;', idx);
      final body = handler.substring(idx, end);
      final sourceIdx = body.indexOf('setAudioSource(');
      final publishIdx = body.indexOf('mediaItem.add(item);');
      final playIdx = body.indexOf('await play();');
      expect(sourceIdx, greaterThanOrEqualTo(0));
      expect(publishIdx, greaterThan(sourceIdx));
      expect(playIdx, greaterThan(publishIdx),
          reason: 'Publish metadata before play — notification must not wait '
              'on the OEM playing flag.');
      expect(body, contains('_ensureAudible(playGen)'));
    });

    test('playFile success is owned MediaItem bind, not lagged playing flag',
        () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<bool> playFile(');
      final end = handler.indexOf('Future<void> _ensureAudible(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('mediaItem.value?.id != path'));
      expect(body, contains('_ensureAudible(playGen)'));
      expect(body, contains('return true;'));
      expect(
        body.contains('audible;'),
        isFalse,
        reason: 'Must not fail the whole session when playing lags.',
      );
      expect(body, contains('suppressMediaSessionPauseEcho = true'));
    });

    test('playClip never stop()s when MediaItem already owns the clip', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_audio.boundPath == clip.filePath'));
      expect(src, contains('never tear down a live MediaSession'));
      expect(
        src.contains(
          'Only wipe the session when nothing is bound',
        ),
        isTrue,
      );
    });

    test('skip keeps manualPlaying session after transport', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('AppPlaybackState.manualPlaying'));
      expect(body, contains('_audio.mediaItem != null'));
      expect(body, contains('suppressMediaSessionPauseEcho = true'));
    });

    test('showsMiniPlayer stays up for titles and session states', () {
      final state = _read('lib/domain/playback/playback_state.dart');
      expect(state, contains('manualPlaying ||'));
      expect(state, contains('scheduledPlaying'));
      expect(state, contains('clipTitle != null || playlistName != null'));
    });

    test('native paused skip prepare keeps scheduledPlaying + titles', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('if (native.isPaused)');
      final end = src.indexOf('// Idle — clear the snapshot', idx);
      final body = src.substring(idx, end);
      expect(body, contains('AppPlaybackState.scheduledPlaying'));
      expect(body, contains('native.clipTitle'));
      expect(body, contains('modalVisible: false'));
    });
  });
}
