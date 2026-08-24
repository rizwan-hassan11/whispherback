// Round 60 contracts superseded by Round 61 where they conflicted with
// session visibility. Keep soft-preempt + native-skip pins that still hold.
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
  group('Round 60 — skip transport hygiene (kept)', () {
    test('soft skip preempt still waits on the transport gate', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<T> _serializeTransport');
      final end =
          src.indexOf('void _refreshScheduleNotificationsDeferred()', idx);
      final body = src.substring(idx, end);
      expect(body, contains('revertOptimisticSkip'));
      expect(body, contains('previous = _transportGate'));
      final softIdx = body.indexOf('} else {');
      expect(softIdx, greaterThanOrEqualTo(0));
      final soft = body.substring(softIdx);
      expect(soft, contains('previous = _transportGate'));
    });

    test('native skip does not claim PLAYING before MediaPlayer.start', () {
      final src = _read(
          'android/app/src/main/kotlin/com/whisperback/whisperback/alarms/WhisperPlaybackService.kt');
      final idx = src.indexOf('private fun handleSkipCommand(');
      final end = src.indexOf('private fun flushPlayerForSkip(', idx);
      final body = src.substring(idx, end);
      expect(body, contains('notifyListener(STATE_PAUSED)'));
      expect(body, contains('playClip(path)'));
      expect(body.contains('writeState(STATE_PLAYING)'), isFalse);
    });

    test('playFile forces audible start via _ensureAudible', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('_ensureAudible(playGen)'));
      expect(handler, contains('mediaItem.add(item)'));
    });
  });
}
