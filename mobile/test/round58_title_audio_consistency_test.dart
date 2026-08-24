// Round 58 — title changed but audio did not; pause/resume changed the clip.
//
// Root causes:
//   1. Optimistic title emit before playFile bound the new source.
//   2. Force-resume after skip replayed whatever ExoPlayer still held.
//   3. Pause/resume reverted an already-committed skip (title ↔ audio split).
//   4. handler.pause ignored ALL pauses during source swap, including user taps.
//   5. currentPath set before bind succeeded.
//   6. Native idle between skip flush/prepare dropped native ownership.
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
  group('Round 58 — title/audio/pause consistency', () {
    test('handler.pause only ignores MediaSession echo during swap', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> pause() async');
      final end = handler.indexOf('Future<void> seek(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_appTransportDepth == 0'));
      expect(body, contains('_sourceSwapInFlight && _appTransportDepth == 0'));
      expect(
        body.contains('if (_sourceSwapInFlight) {\n      if (kDebugMode)'),
        isFalse,
        reason: 'Must not ignore in-app pause during source swap.',
      );
    });

    test('playFile returns bool and currentPath waits for bind success', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('Future<bool> playFile('));
      expect(handler, contains('mediaItem.value?.id == path'));

      final audio = _read('lib/services/audio/audio_services.dart');
      final idx = audio.indexOf('Future<bool> playFile(');
      final end = audio.indexOf('Future<void> warmFileCache(', idx);
      final body = audio.substring(idx, end);
      expect(body, contains('if (ok)'));
      expect(body, contains('_currentPath = path'));
      expect(
        body.indexOf('_currentPath = path'),
        greaterThan(body.indexOf('if (ok)')),
        reason: 'currentPath must be set only after a successful bind.',
      );
      expect(audio, contains('void restoreCurrentPath'));
      expect(audio, contains('String? get boundPath'));
    });

    test('skip does not force-resume after transport', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next) async');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body.contains('await _audio.resume()'), isFalse,
          reason: 'Force-resume after skip replays the old source.');
      expect(body, contains('Do NOT force-resume'));
    });

    test('prime does not emit a new clip title before bind', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _primeOptimisticSkip(bool next)');
      final end = src.indexOf('void _warmLibraryNeighbors()', idx);
      final body = src.substring(idx, end);
      expect(body.contains('_emit('), isFalse,
          reason: 'Optimistic title emit is the title/audio desync.');
      expect(body, contains('_optimisticSkipTargetPath'));
      expect(body, contains('_preSkipBoundPath'));
    });

    test('pause reverts skip only when the new source is not committed', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _abortInFlightTransport(');
      final end = src.indexOf('Future<T> _serializeTransport', idx);
      final body = src.substring(idx, end);
      expect(body, contains('final committed ='));
      expect(body, contains('if (!committed)'));
      expect(body, contains('restoreCurrentPath'));
    });

    test('resume and notification play never revert a committed skip', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final playIdx = src.indexOf('Future<void> _handleNotificationPlay()');
      final playEnd = src.indexOf('Future<void> _systemPause()', playIdx);
      final playBody = src.substring(playIdx, playEnd);
      expect(playBody, contains('revertOptimisticSkip: false'));

      final resumeIdx = src.indexOf('Future<void> resume()');
      final resumeEnd = src.indexOf('Future<void> stop() async', resumeIdx);
      final resumeBody = src.substring(resumeIdx, resumeEnd);
      expect(resumeBody, contains('revertOptimisticSkip: false'));
    });

    test('native idle during skip does not drop native ownership', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('if (_skipInFlight || _suppressTransientNotPlaying)'));
      final idleIdx = src.indexOf(
          '// Idle — clear the snapshot only if we\'d previously promoted it.');
      expect(idleIdx, greaterThanOrEqualTo(0));
      final slice = src.substring(idleIdx, idleIdx + 400);
      expect(slice, contains('_skipInFlight'));
    });

    test('mini-player title follows bound MediaItem, not optimistic snapshot',
        () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('mediaTitle?.isNotEmpty == true ? mediaTitle'));
      expect(bar.contains('skipPending && snapTitle'), isFalse,
          reason: 'Must not prefer optimistic snapshot title during skip.');
    });
  });
}
