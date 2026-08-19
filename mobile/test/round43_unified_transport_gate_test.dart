// Round 43 — skip / pause / play used THREE independent gates
// (_serializeSkip, _serializePauseResume, _serializePlay). They ran
// IN PARALLEL, so tapping Next then Pause while setAudioSource was
// in-flight let pause fire on the old clip while skip still started
// the next one — "I tapped next, nothing happened, then pause played
// the next clip".
//
// Fix: one `_serializeTransport` FIFO + `_transportEpoch` so a newer
// tap supersedes an in-flight skip (via `_honorSupersededTransport`).
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
  group('Round 43 — unified transport gate', () {
    test('pause, resume, skip, and playClip share `_serializeTransport`', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('Future<T> _serializeTransport<T>('));
      expect(src, contains('int _transportEpoch'));
      expect(src, contains('_honorSupersededTransport'));
      expect(src.contains('Future<T> _serializeSkip<T>'), isFalse);
      expect(src.contains('Future<T> _serializePauseResume<T>'), isFalse);
      expect(src.contains('Future<T> _serializePlay<T>'), isFalse);

      final guardedIdx = src.indexOf('Future<void> _guardedSkip(');
      expect(guardedIdx, greaterThanOrEqualTo(0));
      final guardedEnd = src.indexOf('\n  }\n', guardedIdx);
      final guardedBody = src.substring(guardedIdx, guardedEnd);
      expect(guardedBody, contains('_serializeTransport'));
      expect(guardedBody, contains('_skipPlaylistClip'));
      expect(src, contains('(epoch) => _playClipInternal'));
    });

    test('PlaybackSnapshot.showsMiniPlayer drives shell + bar visibility', () {
      final src = _read('lib/domain/playback/playback_state.dart');
      expect(
          src, contains('bool showsMiniPlayer({bool nativeActive = false})'));

      final shell = _read('lib/core/widgets/main_shell.dart');
      expect(shell,
          contains('showsMiniPlayer(nativeActive: native.isNativeActive)'));

      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(
          bar, contains('snapshot.showsMiniPlayer(nativeActive: nativeLive)'));
    });
  });
}
