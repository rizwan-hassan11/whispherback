// Round 52 — after a few pause/resume or next/prev taps the Spotify bar
// vanished with a "Playback failed" snackbar, while the notification card
// kept working. Tapping notification play brought the in-app bar back.
//
// Cause: start-watchdog onPlaybackStartFailure called coordinator.stop(),
// which emitted activeIdle and hid the bar. Pause mid-load left the
// watchdog armed; rapid skips hit aggressive 4s setAudioSource timeouts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whisperback/domain/playback/playback_state.dart';

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
}

void main() {
  group('Round 52 — mini-player stays persistent', () {
    test('start-failure callback must not call stop()', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('_audio.onPlaybackStartFailure = (title)');
      expect(idx, greaterThanOrEqualTo(0));
      final end =
          src.indexOf('_playerSub = _audio.playerStateStream.listen(', idx);
      final body = src.substring(idx, end);
      expect(body.contains('await stop()'), isFalse,
          reason: 'stop() hid the bar while MediaSession stayed alive.');
      expect(body, contains('isPlaying: false'));
      expect(body, contains('manualPlaying'));
    });

    test('handler pause cancels the start watchdog', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> pause() async');
      final end = handler.indexOf('Future<void> seek(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_startWatchdog?.cancel()'));
    });

    test('watchdog is generation-scoped', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('void _scheduleStartWatchdog()');
      final end = handler.indexOf('MediaItem _clipMediaItem(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('expectedGen != _playFileGeneration'));
    });

    test('showsMiniPlayer stays up for media session clip ownership', () {
      const idle = PlaybackSnapshot(state: AppPlaybackState.activeIdle);
      expect(idle.showsMiniPlayer(hasMediaSessionClip: true), isTrue);
      expect(
        const PlaybackSnapshot(state: AppPlaybackState.manualPlaying)
            .showsMiniPlayer(),
        isTrue,
      );
    });

    test('skip failure does not snackbar when audio is still live', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _guardedSkip(');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('stillLive'));
      expect(body, contains('!stillLive && !_errorController.isClosed'));
    });
  });
}
