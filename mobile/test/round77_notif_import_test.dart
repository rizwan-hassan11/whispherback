// Round 77 — sticky notification pause, multi-import, toast placement,
// clip switch, and Spotify-like media notification persistence.
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
  group('Round 77 — notif pause + import polish', () {
    test('MediaSession play re-arms echo suppress under user-pause latch', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('_shouldIgnoreMediaSessionPlay'));
      expect(handler, contains('_userPausedAt'));
      final playIdx = handler.indexOf('Future<void> play() async');
      final playEnd =
          handler.indexOf('Future<void> hideClipMediaNotification(', playIdx);
      final play = handler.substring(playIdx, playEnd);
      expect(play, contains('_armPlayEchoSuppress()'));
      expect(play, contains('_shouldIgnoreMediaSessionPlay'));
    });

    test('notification play handler respects user-pause latch', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPlay()');
      final end = coord.indexOf('Future<void> _systemPause()', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('isUserPausedClip'));
    });

    test('manual preview end parks paused instead of stop()', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _finishManualPreview()');
      final end = coord.indexOf('Future<void> _drainPendingScheduled()', idx);
      final body = coord.substring(idx, end);
      expect(body.contains('await _audio.stop()'), isFalse);
      expect(body, contains('await _audio.pause()'));
      expect(body, contains('AppPlaybackState.manualPlaying'));
    });

    test('playClip primes optimistic switch before transport gate', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_primeOptimisticLibraryPlay'));
      final idx = coord.indexOf('Future<void> playClip(');
      final end = coord.indexOf('void _primeOptimisticLibraryPlay(', idx);
      final body = coord.substring(idx, end);
      expect(body, contains('_primeOptimisticLibraryPlay('));
      expect(body, contains('skipSnapshotEmit: true'));
    });

    test('import allows multiple files', () {
      final src = _read('lib/features/clips/import_screen.dart');
      expect(src, contains('allowMultiple: true'));
      expect(src, contains('importedClipsCount'));
    });

    test('shell snackbar does not double-count reserved bottom height', () {
      final src = _read('lib/core/layout/shell_messenger.dart');
      expect(src.contains('reservedBottomHeight'), isFalse);
      expect(src, contains('EdgeInsets.fromLTRB(12, 0, 12, 8)'));
      expect(src, contains('AppColors.neonCyan'));
    });

    test('build id stamped R77', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R77-notif-import'"));
    });
  });
}
