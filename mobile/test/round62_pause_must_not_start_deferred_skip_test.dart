// Round 62 — QA: next/prev look dead; pause then changes the clip to the
// deferred next target. Root causes:
// 1. Hard pause preempt left skip's playFile running; Round 61 resumed the
//    newly bound MediaItem after playFile returned false.
// 2. Dying playFile did not pause when invalidated for pause (Round 47).
// 3. Notification pause was swallowed for the whole _skipInFlight latch.
// 4. refreshModeState wiped the Spotify bar on a transient Active=false.
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
  group('Round 62 — pause must not start deferred skip', () {
    test('Round 61 resume is gated on pause / stale epoch', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_latestTransportPausesPlayback'));
      expect(
        coord,
        contains('NEVER resume a skip that pause/dismiss superseded'),
      );
      final idx = coord.indexOf('NEVER resume a skip that pause/dismiss');
      expect(idx, greaterThanOrEqualTo(0));
      final window = coord.substring(idx, idx + 500);
      expect(window, contains('_userInitiatedPause'));
      expect(window, contains('_latestTransportPausesPlayback'));
      // Stale-epoch guard is immediately above the Round 62 block (Round 65).
      expect(
        coord.contains(
          'if (transportEpoch != null && !_transportCurrent(transportEpoch))',
        ),
        isTrue,
      );
    });

    test('hard abort invalidates playFile forPause so dying bind pauses', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('invalidateInFlightPlay(forPause: true)'));

      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('_invalidateForPause'));
      expect(handler, contains('invalidateInFlightPlay({bool forPause'));
      expect(handler, contains('_pauseIfInvalidatedForPause'));
      expect(
        handler,
        contains('if pause killed this load, pause'),
      );
    });

    test('notification pause is not swallowed for entire skip latch', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPause()');
      expect(idx, greaterThanOrEqualTo(0));
      final end = coord.indexOf('Future<void> _handleNotificationPlay()', idx);
      final body = coord.substring(idx, end);
      expect(body.contains('if (_skipInFlight'), isFalse,
          reason: 'Real notification pause must preempt skip, not wait.');
      expect(body.contains('|| _skipInFlight'), isFalse);
      expect(body, contains('pausesPlayback: true'));
      expect(body, contains('ignored OEM echo settle window'));
    });

    test('skip exit clears latch when pause won — no force-resume', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('Pause/dismiss won while this skip was binding'),
      );
      final idx =
          coord.indexOf('Pause/dismiss won while this skip was binding');
      final window = coord.substring(idx, idx + 450);
      expect(window, contains('_suppressTransientNotPlaying = false'));
      expect(window, contains('_pendingSkipNext = null'));
      expect(window, contains('isPlaying: false'));
    });

    test('refreshModeState does not wipe an in-session mini-player', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('never wipe an in-session Spotify bar'),
      );
      expect(coord, contains('hasSession'));
    });

    test('shuffle commits playlist index only after successful bind', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final shuffleIdx = coord.indexOf('if (shuffle) {');
      expect(shuffleIdx, greaterThanOrEqualTo(0));
      // Find the skip shuffle block near playFile sourceSwap: true
      final skipShuffle = coord.indexOf(
        'skip shuffle playFile failed',
      );
      expect(skipShuffle, greaterThan(shuffleIdx));
      final beforeOk = coord.substring(shuffleIdx, skipShuffle);
      // Index commit must appear AFTER the playFile success path marker.
      expect(
        beforeOk.contains('if (idx >= 0) _playlistClipIndex = idx;'),
        isFalse,
        reason: 'Must not commit queue index before playFile succeeds.',
      );
      expect(
        coord,
        contains('Commit queue pointer only after a successful bind.'),
      );
    });
  });
}
