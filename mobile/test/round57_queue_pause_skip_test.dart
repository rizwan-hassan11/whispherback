// Round 57 — QA frustrated: loop / pause-skip / dead next-prev
//
// 1. Auto-play looped same clip: keep-alive LoopMode.one survived sourceSwap;
//    playClip from playlist wiped playlistId + cache → single-clip seek(0).
// 2. Pause skipped: completion swallowed by latch OR raced pause sentinel;
//    tiny adjacent hit targets; pause didn't restore skip indices.
// 3. Next/prev dead: notification skipToNext returned when !_playingClip;
//    force-resume on completed seek(0)'d the old track.
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
  group('Round 57 — queue advance, pause, skip reliability', () {
    test('playFile always forces LoopMode.off including sourceSwap', () {
      final src = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> _playFileBound(');
      final end = src.indexOf('void _scheduleStartWatchdog()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('setLoopMode(LoopMode.off)'));
      expect(
        body.contains('if (!swapping) {\n        await _player.setVolume(1);'),
        isFalse,
        reason: 'LoopMode.off must not be gated on !swapping.',
      );
    });

    test('playClip preserves playlistId and clip cache for playlist queues',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('String? playlistId,'));
      final idx = src.indexOf('Future<void> _playClipInternal(');
      final end =
          src.indexOf('\n  /// True when the user is in any clip-playing', idx);
      final body = src.substring(idx, end);
      expect(body, contains('effectivePlaylistId'));
      expect(body, contains('_playlistClipCache = resolvedQueue'));
      expect(body, contains('playlistId: effectivePlaylistId'));
    });

    test('playlist detail playClip passes playlistId', () {
      final src = _read('lib/features/playlists/playlist_detail_screen.dart');
      expect(src, contains('playlistId: widget.playlistId'));
    });

    test('completed is handled before skip latch early-return', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onPlayerState(PlayerState state)');
      final end = src.indexOf('Future<void> _onClipCompleted(', idx);
      final body = src.substring(idx, end);
      final completedIdx = body.indexOf('ProcessingState.completed');
      final latchIdx = body.indexOf('_suppressTransientNotPlaying');
      expect(completedIdx, greaterThanOrEqualTo(0));
      expect(latchIdx, greaterThan(completedIdx),
          reason: 'completed must run before latch swallows the event.');
    });

    test('pause restores pre-skip queue indices and sets sentinel first', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_preSkipLibraryIndex'));
      expect(src, contains('_preSkipPlaylistIndex'));
      final abort = src.substring(
        src.indexOf('Future<void> _abortInFlightTransport('),
        src.indexOf('Future<T> _serializeTransport'),
      );
      expect(abort, contains('_libraryIndex = _preSkipLibraryIndex'));
      expect(abort, contains('_playlistClipIndex = _preSkipPlaylistIndex'));
      expect(abort, contains('if (!committed)'));

      final pauseIdx = src.indexOf('Future<void> pause()');
      final pauseBody = src.substring(pauseIdx, pauseIdx + 500);
      expect(
        pauseBody.indexOf('_userInitiatedPause = true'),
        lessThan(pauseBody.indexOf('_acceptPlayPauseControl')),
      );
    });

    test('notification pause arms user-pause sentinel before transport', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _handleNotificationPause()');
      final end = src.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = src.substring(idx, end);
      expect(
        body.indexOf('_userInitiatedPause = true'),
        lessThan(body.indexOf('_serializeTransport')),
        reason: 'Notification shade pause must not lose the completion race.',
      );
    });

    test('duplicate completion events cannot double-advance queue', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_clipCompletionInFlight'));
      final idx = src.indexOf('Future<void> _onClipCompleted() async');
      final end = src.indexOf('Future<void> _onClipCompletedBody() async', idx);
      final guard = src.substring(idx, end);
      expect(guard, contains('if (_clipCompletionInFlight) return'));
    });

    test('notification skip routes to coordinator even when not playingClip',
        () {
      final src = _read('lib/services/audio/whisper_audio_handler.dart');
      final nextIdx = src.indexOf('Future<void> skipToNext() async');
      final prevIdx = src.indexOf('Future<void> skipToPrevious() async');
      final nextBody = src.substring(nextIdx, prevIdx);
      final onNextIdx = nextBody.indexOf('onSkipToNextRequested');
      final playingIdx = nextBody.indexOf('if (!_playingClip) return;');
      expect(onNextIdx, greaterThanOrEqualTo(0));
      expect(playingIdx, greaterThan(onNextIdx),
          reason: 'Coordinator callback must win before playingClip gate.');
    });

    test('mini-player transport controls meet 48dp touch targets', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('width: 48'));
      expect(bar, contains('height: 48'));
      expect(bar, contains('SizedBox(width: 6)'));
    });
  });
}
