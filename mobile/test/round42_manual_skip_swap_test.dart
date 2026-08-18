// Round 42 — manual library / playlist skip felt dead, then surfaced
// "Couldn't play …" for the clip that was already playing (see QA
// screenshot: Clip Library, 3 imported clips, next on Winter Time).
//
// Root cause: `_playClipInternal` called `_audio.stop()` before every
// clip swap. stop() → stopClip() → silence keep-alive restart on
// Active=ON, which raced the incoming playFile/setAudioSource. The 5s
// start watchdog then fired for the stale title while skip was wedged.
//
// Fix: playFile swaps sources with `_player.stop()` only (never
// stopClip), and `_playClipInternal` no longer pre-flights stop().
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
  group('Round 42 — manual skip clip swap (just_audio path)', () {
    test('_playClipInternal no longer calls _audio.stop() before playFile', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _playClipInternal(');
      expect(idx, greaterThanOrEqualTo(0));
      final end =
          src.indexOf('\n  /// True when the user is in any clip-playing', idx);
      expect(end, greaterThan(idx));
      final body = src.substring(idx, end);
      expect(body.contains('await _audio.stop()'), isFalse,
          reason: 'stop() restarts silence keep-alive and races the next '
              'setAudioSource during library/playlist skip.');
      expect(body, contains('await _audio.playFile('),
          reason: 'Clip swap must go straight into playFile.');
    });

    test('playFile swaps with _player.stop() only, never stopClip()', () {
      final src = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = src.indexOf('Future<void> playFile(');
      expect(idx, greaterThanOrEqualTo(0));
      final end = src.indexOf('\n  /// Outstanding watchdog', idx);
      final body = src.substring(idx, end);
      expect(body, contains('if (_playingClip)'),
          reason: 'An in-flight clip must take the swap path.');
      expect(body, contains('await _player.stop()'),
          reason: 'ExoPlayer source must be cleared before setAudioSource.');
      expect(body, contains('never `stopClip()`'),
          reason: 'Document the silence keep-alive race explicitly.');
      expect(body.contains('await stopClip()'), isFalse,
          reason: 'playFile must not tear down to silence mid-swap.');
    });

    test(
        'library skip emits optimistic snapshot before playClip and '
        'multi-clip library auto-advances on completion', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');

      final skipIdx = src.indexOf('Future<void> _skipPlaylistClip(');
      expect(skipIdx, greaterThanOrEqualTo(0));
      final skipEnd =
          src.indexOf('\n  Future<void> _playClipAtIndex(', skipIdx);
      final skipBody = src.substring(skipIdx, skipEnd);
      expect(skipBody, contains('Optimistic UI so next/prev feels instant'),
          reason: 'Manual skip must not wait for setAudioSource to update '
              'the mini-player title.');

      final completeIdx = src.indexOf('Future<void> _onClipCompleted(');
      expect(completeIdx, greaterThanOrEqualTo(0));
      final completeEnd = src.indexOf(
          '\n  /// Walks [clips] starting at [startIndex]', completeIdx);
      final completeBody = src.substring(completeIdx, completeEnd);
      expect(completeBody, contains('if (_libraryQueue.length > 1)'),
          reason: 'A 3-clip library queue must advance on natural end, not '
              'stop after every track.');
    });
  });
}
