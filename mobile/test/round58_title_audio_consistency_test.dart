// Round 58 — title/audio/pause consistency (updated by Round 59 where needed).
//
// Still pinned:
//   - handler.pause only ignores MediaSession echo during swap
//   - currentPath waits for bind success
//   - resume/notification play never revertOptimisticSkip
//   - native idle during skip keeps ownership
//
// Round 59 revised:
//   - skip may ensure-playing after transport (OEM pause-echo)
//   - prime emits title again for first-tap feedback
//   - pause never reverts clip identity
//   - mini-player may prefer snapshot title while skip is in flight
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
      expect(body, contains('suppressMediaSessionPauseEcho'));
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
      expect(handler, contains('_waitUntilPlaying'));
      expect(handler, contains('_player.playing'));
      expect(
        handler.contains('Bound for this path counts as success even if'),
        isFalse,
        reason: 'Bind-without-play made next dead until pause/resume.',
      );

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

    test('skip ensure-playing is gated on pause intent', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next) async');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_latestTransportPausesPlayback || _userInitiatedPause'));
      expect(body, contains('await _audio.resume()'));
    });

    test('prime emits skip title for instant feedback', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('void _primeOptimisticSkip(bool next)');
      final end = src.indexOf('void _warmLibraryNeighbors()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('_emit('));
      expect(body, contains('clipTitle: clip.title'));
      expect(body, contains('_optimisticSkipTargetPath'));
    });

    test('pause abort never changes clip identity', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _abortInFlightTransport(');
      final end = src.indexOf('Future<T> _serializeTransport', idx);
      final body = src.substring(idx, end);
      expect(body, contains('must NEVER change which clip'));
      expect(body.contains('final committed ='), isFalse);
      expect(body.contains('_libraryIndex = _preSkipLibraryIndex'), isFalse);
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

    test('mini-player may prefer snapshot title while skip is pending', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('skipPending && snapTitle'));
      expect(bar, contains('mediaTitle?.isNotEmpty == true ? mediaTitle'));
    });
  });
}
