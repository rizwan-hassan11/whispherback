// Round 50 — next/prev still paused the new clip; mini-player hid / went stale.
//
// Root cause: ExoPlayer stop() during source swap makes Android MediaSession
// echo a PAUSE into audio_service → onPauseRequested → real pause after skip.
// Combined with playerState syncing playing:false into the snapshot.
//
// Fix:
//   1. Ignore handler.pause / notification pause during source swap / skip latch
//   2. Never auto-pause snapshot from playerState (pause is user/coordinator only)
//   3. Force resume + isPlaying:true after every skip
//   4. showsMiniPlayer always true for manualPlaying/scheduledPlaying sessions
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
  group('Round 50 — skip always plays + mini-player session visibility', () {
    test('handler.pause ignores only MediaSession echo during source swap', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> pause() async');
      expect(idx, greaterThanOrEqualTo(0));
      final end = handler.indexOf('Future<void> seek(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('suppressMediaSessionPauseEcho'));
      expect(body, contains('_appTransportDepth == 0'));
      expect(body, contains('return;'));
    });

    test('notification pause ignored during skip latch', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _handleNotificationPause()');
      final end = src.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_suppressTransientNotPlaying'));
      expect(body, contains('_skipInFlight'));
      expect(body, contains('return Future<void>.value()'));
    });

    test('guardedSkip ensure-playing after transport when not paused', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next) async');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('await _audio.resume()'));
      expect(body, contains('_userInitiatedPause'));
    });

    test('onPlayerState never auto-pauses from playing:false', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onPlayerState(PlayerState state)');
      final end = src.indexOf('Future<void> _onClipCompleted(', idx);
      final body = src.substring(idx, end);
      // Round 51: skip latch still swallows transient false; user pause syncs.
      expect(body, contains('if (_suppressTransientNotPlaying)'));
      expect(body, isNot(contains('NEVER auto-pause')));
    });

    test('manualPlaying session always shows mini-player', () {
      const snap = PlaybackSnapshot(
        state: AppPlaybackState.manualPlaying,
      );
      expect(snap.showsMiniPlayer(), isTrue,
          reason:
              'Bar must show for the whole play session, even without titles.');
    });

    test('mini-player does not shrink after showsMiniPlayer for missing titles',
        () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(
        bar.contains(
            'if (title == null && subtitle == null && !nativeLive && !dartClipActive)'),
        isFalse,
        reason: 'Title-gap shrink made the bar invisible mid skip.',
      );
      expect(bar, contains('mediaItemStream'));
      expect(bar, contains('audio.isPlayingClip'));
      expect(bar, contains('coordinator.skipTransportActive'));
    });
  });
}
