// Round 49 — next/prev alternated pause then play; mini-player kept the
// old title and 00:00 after the audio already changed.
//
// Causes:
//   1. `_suppressTransientNotPlaying` cleared in `finally` right after
//      await playFile, so a late ready+playing:false synced isPlaying=false.
//      Next skip started "paused" and settled playing → alternate.
//   2. Mini-player preferred stale snapshot.clipTitle over native title;
//      StreamBuilders were not keyed by clip so progress stayed at 0.
//
// Fix: keep the skip latch until playing:true (or user pause); clear
// `_sourceSwapInFlight` only when ExoPlayer reports playing; prefer native
// titles when native owns audio; key progress StreamBuilders by clip.
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
  group('Round 49 — skip latch + mini-player metadata', () {
    test('skip latch is not cleared in guardedSkip finally', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _guardedSkip(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_suppressTransientNotPlaying = true'));
      expect(body.contains('} finally {'), isFalse,
          reason: 'Clearing in finally reintroduced alternate pause/play.');
      // Native-only clear after emit is OK — Dart keeps latch until playing:true.
      expect(body, contains('isPlaying: true'));
      expect(body, contains('await _audio.resume()'));
    });

    test('onPlayerState never syncs playing:false into snapshot', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _onPlayerState(PlayerState state)');
      final end = src.indexOf('Future<void> _onClipCompleted(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('if (!playing) {\n          return;'));
      expect(body, contains('_emit(_snapshot.copyWith(isPlaying: true))'));
    });

    test('handler clears sourceSwapInFlight when player is playing', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final broadcastIdx =
          handler.indexOf('void _broadcastState(PlaybackEvent event)');
      final broadcastEnd =
          handler.indexOf('static const _stopControl', broadcastIdx);
      final broadcast = handler.substring(broadcastIdx, broadcastEnd);
      expect(broadcast, contains('if (_player.playing)'));
      expect(broadcast, contains('_sourceSwapInFlight = false'));
    });

    test('mini-player merges titles by ownership and keys progress by clip', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('final dartOwns = audio.currentPath != null'));
      expect(bar, contains('ValueKey<String>'));
      expect(bar, contains('key: progressKey'));
      expect(bar, contains('displayPlaying = snapshot.isPlaying'));
      expect(bar, contains('audio.isPlayingClip || audio.isPlaying'));
    });
  });
}
