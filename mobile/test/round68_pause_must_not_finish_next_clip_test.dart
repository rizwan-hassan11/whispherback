// Round 68 — pause during next/prev was still changing the audible clip.
// Commit-on-tap put index/title on B while a dying playFile finished
// setAudioSource(B) under the pause finger. Fix: on hard pause, capture the
// bound path, cancelInFlightPlay to kill the swap, snap queue+title back to
// that bound clip, then pause. Handler also refuses flush/setAudioSource
// after a pause invalidate.
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
  group('Round 68 — pause must not finish the next clip', () {
    test('hard abort cancels in-flight swap and reconciles to bound path', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      final end = coord.indexOf('Future<T> _serializeTransport', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('boundBefore'));
      expect(body, contains('await _audio.cancelInFlightPlay()'));
      expect(body, contains('_reconcileSessionToBoundPath'));
      expect(body, contains('invalidateInFlightPlay(forPause: true)'));
    });

    test('reconcile sets library/playlist index from bound path', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('void _reconcileSessionToBoundPath('));
      final idx = coord.indexOf('void _reconcileSessionToBoundPath(');
      final body = coord.substring(idx, idx + 1200);
      expect(body, contains('_libraryIndex = idx'));
      expect(body, contains('_playlistClipIndex = idx'));
      expect(body, contains('filePath == path'));
    });

    test('playFileBound refuses flush/swap after pause invalidate', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _playFileBound(');
      final end = handler.indexOf('await _flushPlayerSource();', idx);
      final beforeFlush = handler.substring(idx, end);
      expect(
        beforeFlush.contains('playGen != _playFileGeneration'),
        isTrue,
        reason: 'Must check generation before flushing the current clip.',
      );
    });
  });
}
