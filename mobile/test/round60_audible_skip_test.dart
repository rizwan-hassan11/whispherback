// Round 60 — next/prev still dead; pause/resume then plays the skipped clip;
// Spotify mini-player still vanishes.
//
// Root cause (not another flag):
//   1. playFile returned success when MediaItem was bound even if ExoPlayer
//      was NOT playing — skip committed a silent next clip.
//   2. Soft skip preempt jumped the transport gate, interleaving setAudioSource.
//   3. Skip UI forced isPlaying:true after a silent bind.
//   4. Native skip notified STATE_PLAYING before MediaPlayer.start().
//   5. Native idle demoted to bare activeIdle and hid the mini-player.
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
  group('Round 60 — skip is audible before commit', () {
    test('playFile succeeds only when path bound AND playing', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<bool> playFile(');
      final end = handler.indexOf('Future<bool> _waitUntilPlaying(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('mediaItem.value?.id == path'));
      expect(body, contains('_player.playing'));
      expect(body, contains('_waitUntilPlaying(playGen)'));
      expect(
        body.contains('Bound for this path counts as success'),
        isFalse,
      );
    });

    test('playFile publishes MediaItem only after audible play', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _playFileBound(');
      final end = handler.indexOf('Timer? _startWatchdog;', idx);
      final body = handler.substring(idx, end);
      final playIdx = body.indexOf('await play();');
      final publishIdx = body.indexOf('mediaItem.add(item);');
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(publishIdx, greaterThan(playIdx),
          reason: 'Publishing MediaItem before play made silent binds the '
              'current clip that pause/resume then started.');
      expect(body, contains('if (playGen != _playFileGeneration || !_player.playing)'));
    });

    test('soft skip preempt still waits on the transport gate', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<T> _serializeTransport');
      final end = src.indexOf('void _refreshScheduleNotificationsDeferred()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('revertOptimisticSkip'));
      expect(body, contains('previous = _transportGate'));
      // Soft branch must NOT jump the gate with Future.value().
      final softIdx = body.indexOf('} else {');
      expect(softIdx, greaterThanOrEqualTo(0));
      final soft = body.substring(softIdx);
      expect(soft, contains('previous = _transportGate'));
    });

    test('skip never paints isPlaying true when audio is silent', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _runOneSkip(bool next) async');
      final end = src.indexOf('Future<void> _skipPlaylistClip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('isPlaying: audible'));
      expect(
        body.contains('isPlaying: true,\n            modalVisible: false'),
        isFalse,
        reason: 'Forcing isPlaying:true after a silent skip lied to the UI.',
      );
    });

    test('native idle keeps session titles so the mini-player stays', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('hasSessionMeta'));
      expect(src, contains('_snapshot.clipTitle != null || _snapshot.playlistName != null'));
      expect(
        src.contains(
          '// Keep scheduledPlaying + titles so the bar never vanishes mid-skip.',
        ),
        isTrue,
      );
    });

    test('native skip does not claim PLAYING before MediaPlayer.start', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun handleSkipCommand(');
      final end = src.indexOf('private fun flushPlayerForSkip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('notifyListener(STATE_PAUSED)'));
      expect(body, contains('playClip(path)'));
      // Early PLAYING before prepare is the native twin of the Dart bug.
      expect(
        body.contains('writeState(STATE_PLAYING)'),
        isFalse,
      );
    });
  });
}
