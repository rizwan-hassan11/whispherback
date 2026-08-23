// Round 54 — QA Aug 22 stability pass
//
// Issue 1 (P0): splash / bootstrap could hang forever on reopen → black screen.
// Issue 2 (P1): rapid next taps primed the queue twice (2-clip wrap = replay).
// Issue 3 (P1): no debounce on play/skip → erratic double-tap state.
//
// Also: MediaSession skipToNext must route through the coordinator whenever
// wired, not only when `_playlistMode` is true (that flag can clear mid-session
// and turn next into seek(0) replay).
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
  group('Round 54 — crash / skip / double-tap stability', () {
    test('skip queues overlapping taps; no time debounce on skip', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('static const _controlDebounce'));
      expect(src, contains('bool _skipInFlight = false'));
      expect(src, contains('bool? _pendingSkipNext'));
      expect(src, contains('bool get skipTransportActive'));
      expect(src, contains('bool _acceptPlayPauseControl()'));
      expect(src.contains('_acceptSkipControl'), isFalse);

      final runIdx = src.indexOf('Future<void> _runOneSkip(');
      expect(runIdx, greaterThanOrEqualTo(0));
      final runEnd = src.indexOf('\n  Future<void> _skipPlaylistClip(', runIdx);
      final runBody = src.substring(runIdx, runEnd);
      expect(runBody, contains('_primeOptimisticSkip(next);'));
      expect(runBody.contains('flushCurrentSource'), isFalse);
      final primeIdx = runBody.indexOf('_primeOptimisticSkip(next);');
      final transportIdx = runBody.indexOf('_serializeTransport');
      expect(transportIdx, greaterThan(primeIdx));
    });

    test('pause and resume share a play/pause debounce gate', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final pauseIdx = src.indexOf('Future<void> pause()');
      final resumeIdx = src.indexOf('Future<void> resume()');
      expect(pauseIdx, greaterThanOrEqualTo(0));
      expect(resumeIdx, greaterThan(pauseIdx));

      final pauseBody = src.substring(pauseIdx, resumeIdx);
      expect(pauseBody, contains('if (!_acceptPlayPauseControl()) return'));

      final resumeEnd = src.indexOf('\n  Future<void> ', resumeIdx + 1);
      final resumeBody = src.substring(
        resumeIdx,
        resumeEnd > resumeIdx ? resumeEnd : resumeIdx + 400,
      );
      expect(resumeBody, contains('if (!_acceptPlayPauseControl()) return'));
    });

    test('MediaSession next/prev prefer coordinator over playlistMode seek-0',
        () {
      final src = _read('lib/services/audio/whisper_audio_handler.dart');
      final nextIdx = src.indexOf('Future<void> skipToNext() async');
      final prevIdx = src.indexOf('Future<void> skipToPrevious() async');
      expect(nextIdx, greaterThanOrEqualTo(0));
      expect(prevIdx, greaterThan(nextIdx));

      final nextBody = src.substring(nextIdx, prevIdx);
      expect(nextBody, contains('onSkipToNextRequested'));
      expect(
        nextBody.contains('if (_playlistMode)'),
        isFalse,
        reason: 'Gate on callback presence, not _playlistMode.',
      );
      expect(nextBody, contains('final onNext = onSkipToNextRequested;'));
      expect(nextBody, contains('if (onNext != null)'));
    });

    test('splash and bootstrap cannot hang forever on reopen', () {
      final splash = _read('lib/features/splash/splash_screen.dart');
      expect(splash, contains('_bootstrapTimeout'));
      expect(splash, contains('Duration(seconds: 8)'));
      expect(splash, contains('_ensureReadyWithCap'));
      expect(splash, contains('_bootstrapCap?.cancel()'));
      expect(
        splash.contains('.timeout(_bootstrapTimeout)'),
        isFalse,
        reason:
            'Future.timeout leaves a pending Timer that breaks widget_test.',
      );

      final boot = _read('lib/core/bootstrap/app_bootstrap.dart');
      expect(boot, contains('reconcileOrphanClipFiles'));
      expect(boot, contains('.timeout(const Duration(seconds: 3))'));

      final bridge = _read('lib/services/scheduler/native_alarms_bridge.dart');
      final fetchIdx =
          bridge.indexOf('Future<NativePlaybackSnapshot> fetchPlaybackState');
      expect(fetchIdx, greaterThanOrEqualTo(0));
      final fetchBody = bridge.substring(fetchIdx, fetchIdx + 900);
      expect(fetchBody, contains('.timeout(const Duration(seconds: 2))'));
    });
  });
}
