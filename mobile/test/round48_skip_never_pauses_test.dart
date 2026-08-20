// Round 48 — first next/prev tap looked like pause; notification skip
// changed the title then paused; mini-player hid after a few skips.
//
// Cause: playFile source-swap calls `_player.stop()`, which briefly
// reports playing:false. That was synced into PlaybackSnapshot and the
// media notification. Skip failures also called full stop() → activeIdle.
//
// Fix: suppress transient not-playing during skip; keep notification
// publishing playing during `_sourceSwapInFlight`; never tear down the
// mini-player on a skip playFile failure.
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
  group('Round 48 — next/prev must never pause', () {
    test('coordinator ignores transient not-playing during skip swap', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('_suppressTransientNotPlaying'));
      expect(src, contains('_suppressTransientNotPlaying = true'));

      final onIdx = src.indexOf('void _onPlayerState(PlayerState state)');
      expect(onIdx, greaterThanOrEqualTo(0));
      final onEnd = src.indexOf('Future<void> _onClipCompleted(', onIdx);
      final body = src.substring(onIdx, onEnd);
      expect(body, contains('if (!playing && !_userInitiatedPause && _suppressTransientNotPlaying)'));
      expect(body, contains('ProcessingState.idle'));
    });

    test('handler keeps notification playing during source swap', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('bool _sourceSwapInFlight = false'));
      expect(handler, contains('_sourceSwapInFlight = swapping'));

      final broadcastIdx = handler.indexOf('void _broadcastState(PlaybackEvent event)');
      expect(broadcastIdx, greaterThanOrEqualTo(0));
      final broadcastEnd = handler.indexOf('static const _stopControl', broadcastIdx);
      final broadcast = handler.substring(broadcastIdx, broadcastEnd);
      expect(broadcast, contains('if (_sourceSwapInFlight)'));
      expect(broadcast, contains('playing: true'));
    });

    test('library skip playFile failure does not call stop()', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      final idx = src.indexOf('Future<void> _playClipInternal(');
      final end =
          src.indexOf('\n  /// True when the user is in any clip-playing', idx);
      final body = src.substring(idx, end);
      expect(body, contains('if (skipSnapshotEmit)'));
      final skipFail = body.indexOf('if (skipSnapshotEmit)');
      final stopIdx = body.indexOf('await stop()', skipFail);
      // The skip-failure branch must return before any stop().
      final returnIdx = body.indexOf('return;', skipFail);
      expect(returnIdx, greaterThan(skipFail));
      expect(stopIdx == -1 || stopIdx > returnIdx, isTrue,
          reason: 'skipSnapshotEmit failure must not tear down via stop().');
    });
  });
}
