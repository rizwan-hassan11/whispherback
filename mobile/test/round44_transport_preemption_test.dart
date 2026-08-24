// Round 44 — FIFO transport let pause queue BEHIND an in-flight skip.
// Skip finished playFile, started the next clip, then pause ran — the
// user saw "pause changed the clip". Notification pause only synced
// snapshot and never preempted skip.
//
// Fix: preempting transport (pause/resume cut the line), optimistic skip
// revert, cancelInFlightPlay, native pending-skip cancel on pause.
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
  group('Round 44 — transport preemption', () {
    test('pause and notification handlers preempt in-flight skip', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_abortInFlightTransport'));
      expect(coord, contains('_optimisticSkipIndex'));
      expect(coord, contains('bool preempt = false'));
      expect(coord, contains('revertOptimisticSkip: true'));
      expect(coord, contains('_handleNotificationPause'));
      expect(coord, contains('_handleNotificationPlay'));
      expect(
          coord,
          contains(
              'onPauseRequested = () => unawaited(_handleNotificationPause())'));
      expect(
          coord,
          isNot(contains(
              'onPauseRequested = () => _syncPlayingSnapshot(false)')));

      final pauseIdx = coord.indexOf('Future<void> pause()');
      expect(pauseIdx, greaterThanOrEqualTo(0));
      final pauseEnd =
          coord.indexOf('\n  /// Pauses the current clip', pauseIdx);
      final pauseBody = coord.substring(pauseIdx, pauseEnd);
      expect(pauseBody, contains('preempt: true'));
      expect(pauseBody, contains('revertOptimisticSkip: true'));
    });

    test('playFile fast swap + neighbor cache warm', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('bool sourceSwap = false'));
      expect(handler, contains('Future<void> warmFileCache(String path)'));
      expect(handler, contains('AudioSource.file(path)'));

      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_primeOptimisticSkip'));
      expect(coord, contains('_playlistClipCache'));
      expect(coord, contains('_warmLibraryNeighbors'));
    });

    test('native service cancels deferred skip on pause', () {
      final kt = _read(
        'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt',
      );
      expect(kt, contains('skipGeneration'));
      expect(kt, contains('skipRevertPath'));
      expect(kt, contains('if (userPaused) return@post'));
    });
  });
}
