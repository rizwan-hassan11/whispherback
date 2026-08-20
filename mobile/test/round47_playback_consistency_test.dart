// Round 47 — QA: mini-player hides while audio plays, scrubber stuck at
// 00:00, next/prev / notification inconsistent after latency work.
//
// Fixes pinned here:
//   1. `_honorSupersededTransport` only pauses when latest intent is pause
//      (skip→skip must not pause the newer clip).
//   2. Mini-player progress uses Dart streams whenever a Dart clip path
//      exists — never OR bare nativeLive (stale native positionMs=0).
//   3. showsMiniPlayer accepts dartClipActive so handoff races keep the bar.
//   4. playFile keeps preload:true and does not pause a newer generation.
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
  group('Round 47 — playback consistency', () {
    test('honor superseded only pauses when latest transport pauses playback',
        () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('bool _latestTransportPausesPlayback'));
      expect(src, contains('bool pausesPlayback = false'));
      expect(src, contains('pausesPlayback: true'));

      final honorIdx = src.indexOf('Future<void> _honorSupersededTransport(');
      expect(honorIdx, greaterThanOrEqualTo(0));
      final honorEnd = src.indexOf('\n  /// Called after a scheduled whisper', honorIdx);
      final honor = src.substring(honorIdx, honorEnd);
      expect(honor, contains('if (!_latestTransportPausesPlayback) return'));
      expect(honor, contains('await _audio.pause()'));
    });

    test('mini-player progress never ORs bare nativeLive', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar.contains('_useNativeProgress(snapshot, audio) ||\n                                    nativeLive'),
          isFalse);
      expect(bar.contains('_useNativeProgress(snapshot, audio) || nativeLive'),
          isFalse);
      expect(bar, contains('stream: _useNativeProgress(snapshot, audio)'));
    });

    test('showsMiniPlayer stays up for dartClipActive handoff', () {
      final withTitles = const PlaybackSnapshot(
        state: AppPlaybackState.activeIdle,
        clipTitle: 'Winter Time',
        playlistName: 'Library',
      );
      expect(withTitles.showsMiniPlayer(), isTrue,
          reason: 'Titles keep the bar during activeIdle handoff.');
      expect(
        withTitles.showsMiniPlayer(dartClipActive: true),
        isTrue,
      );
      expect(withTitles.showsMiniPlayer(nativeActive: true), isTrue);

      final bareIdle =
          const PlaybackSnapshot(state: AppPlaybackState.activeIdle);
      expect(bareIdle.showsMiniPlayer(), isFalse);
      expect(bareIdle.showsMiniPlayer(dartClipActive: true), isTrue);

      final playing = const PlaybackSnapshot(
        state: AppPlaybackState.manualPlaying,
        clipTitle: 'A',
      );
      expect(playing.showsMiniPlayer(), isTrue);
    });

    test('playFile preload stays true and does not pause newer generation', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> playFile(');
      final end = handler.indexOf('\n  /// Outstanding watchdog', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('preload: true'));
      expect(body.contains('preload: !swapping'), isFalse);
      expect(
        body.contains('await _player.pause()'),
        isFalse,
        reason: 'Superseded playFile must not pause the newer clip.',
      );
      expect(body, contains('await _player.stop()'));
    });
  });
}
