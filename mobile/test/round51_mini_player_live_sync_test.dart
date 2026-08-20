// Round 51 — notification card updated correctly; in-app Spotify bar did not
// (pause icon stuck, stale title/timestamps, bar flickering invisible).
//
// Root cause: coordinator.pause/playFile → handler.pause/play called
// onPauseRequested/onPlayRequested, which re-entered notification transport
// with preempt + revertOptimisticSkip — reverting skip titles and fighting
// the snapshot. Mini-player also painted from snapshot only instead of the
// same MediaSession streams the notification uses.
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
  group('Round 51 — mini-player live sync with MediaSession', () {
    test('handler does not echo pause/play callbacks during app transport', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('int _appTransportDepth = 0'));
      expect(handler, contains('runFromAppTransport'));
      expect(handler, contains('if (_appTransportDepth == 0)'));
      expect(handler, contains('onPauseRequested?.call()'));
      expect(handler, contains('onPlayRequested?.call()'));
    });

    test('AudioPlaybackService routes pause/resume/playFile via app transport',
        () {
      final audio = _read('lib/services/audio/audio_services.dart');
      expect(audio, contains('runFromAppTransport(_handler.pause)'));
      expect(audio, contains('runFromAppTransport(_handler.play)'));
      expect(audio, contains('runFromAppTransport('));
      expect(audio, contains('mediaItemStream'));
      expect(audio, contains('playbackStateStream'));
    });

    test('notification pause is a no-op when already user-paused', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _handleNotificationPause()');
      final end = src.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_userInitiatedPause && !_snapshot.isPlaying'));
    });

    test('onPlayerState syncs pause when user-initiated; latch only on skip',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onPlayerState(PlayerState state)');
      final end = src.indexOf('Future<void> _onClipCompleted(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('if (_userInitiatedPause)'));
      expect(body, contains('if (_suppressTransientNotPlaying)'));
      expect(body, contains('_emit(_snapshot.copyWith(isPlaying: playing))'));
    });

    test('mini-player follows mediaItem and mediaSession playing', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('mediaItemStream'));
      expect(bar, contains('playbackStateStream'));
      expect(bar, contains('mediaSessionPlaying'));
      expect(bar, contains('displayPlaying = dartOwns'));
    });
  });
}
