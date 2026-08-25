// Round 59 — next/prev dead; pause/resume after skip changes clip; mini-player hides.
//
// Causes:
//   1. Pause abort reverted indices/titles after a skip bind (path mismatch /
//      uncleared markers) so resume rebound a different clip.
//   2. playFile required generation match after play() — false negatives left
//      audio stopped while the session looked "skipped".
//   3. Queue indices advanced in prime before bind; cancelled skips stranded
//      the pointer on a clip that never played.
//   4. Mini-player dartClipActive ignored skip-in-flight / MediaSession gaps.
//   5. stop()/setAudioSource during skip emitted `completed` → auto-advance
//      raced the skip's playFile (next dead; pause/resume played raced clip).
//   6. MediaSession pause echo after `_sourceSwapInFlight` cleared paused the
//      new clip; hard abort used stop() which destroyed the bound source.
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
  group('Round 59 — skip works; pause does not change clip; bar stays', () {
    test('pause abort never restores pre-skip indices or titles', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _abortInFlightTransport(');
      final end = src.indexOf('Future<T> _serializeTransport', idx);
      final body = src.substring(idx, end);
      // Round 67: pause never restores indices or titles.
      expect(body.contains('_libraryIndex = _preSkipLibraryIndex'), isFalse);
      expect(
          body.contains('_playlistClipIndex = _preSkipPlaylistIndex'), isFalse);
      expect(body.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(body.contains('cancelInFlightPlay'), isFalse);
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
      expect(body, contains('await _audio.pause()'));
    });

    test('prime emits target title but does not advance queue indices', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _primeOptimisticSkip(bool next)');
      final end = src.indexOf('void _warmLibraryNeighbors()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_emit('));
      expect(body, contains('clipTitle: clip.title'));
      // Round 67: index IS committed on tap (Spotify-like). Body must not
      // advance a second time from the old pointer.
      expect(body, contains('_libraryIndex = nextIndex'));
      expect(body, contains('_playlistClipIndex = nextIndex'));
    });

    test('playFile success requires audible playing, not just mediaItem bind',
        () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<bool> playFile(');
      final end = handler.indexOf('Future<void> _ensureAudible(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_ensureAudible(playGen)'));
      expect(body, contains('isExoBoundTo(path)'));
      expect(body, contains('return true;'));
      expect(
        body.contains('Bound for this path counts as success even if'),
        isFalse,
      );
    });

    test('skip ensures playing after transport when not user-paused', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('await _audio.resume()'));
      expect(body,
          contains('_latestTransportPausesPlayback || _userInitiatedPause'));
      expect(body, contains('suppressMediaSessionPauseEcho = true'));
      // Round 71: post-skip pause-ignore window removed (blocked real pause).
      expect(body.contains('_ignoreSessionPauseUntil'), isFalse);
    });

    test('resume prefers boundPath over stale currentPath', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> resume()');
      final end = src.indexOf('Future<void> stop() async', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_audio.boundPath ?? _audio.currentPath'));
      expect(
        body.contains('boundPath != null && _audio.boundPath != path'),
        isFalse,
        reason: 'Must not rebind an older path over the bound MediaItem.',
      );
    });

    test('completed during skip does not auto-advance', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onPlayerState(PlayerState state)');
      final end = src.indexOf('Future<void> _onClipCompleted()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('ProcessingState.completed'));
      expect(body, contains('_skipInFlight || _suppressTransientNotPlaying'));
      expect(
        body.indexOf('if (_skipInFlight || _suppressTransientNotPlaying)'),
        lessThan(body.indexOf('unawaited(_onClipCompleted())')),
      );
    });

    test('handler ignores MediaSession pause echo during source swap only', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('suppressMediaSessionPauseEcho'));
      final idx = handler.indexOf('Future<void> pause() async');
      final end = handler.indexOf('Future<void> seek(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_sourceSwapInFlight &&'));
      expect(body, contains('!_player.playing'));
      expect(body, contains('_appTransportDepth == 0'));
      expect(
        body.contains('(_sourceSwapInFlight || suppressMediaSessionPauseEcho)'),
        isFalse,
      );
    });

    test('mini-player stays up during skip and prefers snapshot title', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('coordinator.skipTransportActive'));
      expect(bar, contains('snapTitle?.isNotEmpty == true'));
      expect(bar.contains('skipPending || snapshot.isPlaying'), isFalse);
      expect(bar, contains('elevation: 8'));
      final shell = _read('lib/core/widgets/main_shell.dart');
      expect(shell, contains('skipTransportActive'));
      final state = _read('lib/domain/playback/playback_state.dart');
      expect(state, contains('clipTitle != null || playlistName != null'));
    });
  });
}
