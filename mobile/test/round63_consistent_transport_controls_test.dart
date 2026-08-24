// Round 63 — next/prev/pause felt dead because the mini-player preferred
// stale MediaSession title/playing over the coordinator snapshot, sticky
// nativeActive stole library skips onto skipNative, and pause debounce
// could flip the icon without pausing audio.
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
  group('Round 63 — consistent transport controls', () {
    test('mini-player prefers snapshot title and isPlaying', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('Round 63: in-app bar follows the coordinator'));
      expect(bar, contains('snapTitle?.isNotEmpty == true'));
      expect(bar, contains('skipPending || snapshot.isPlaying'));
      expect(
        bar.contains('skipPending ? true : mediaSessionPlaying'),
        isFalse,
        reason: 'Must not drive the play icon from lagged MediaSession.',
      );
    });

    test('native transport only while scheduledPlaying', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('state == AppPlaybackState.scheduledPlaying &&'),
      );
      expect(coord, contains('Sticky `nativeActive` prefs'));
    });

    test('skip finally clears suppress latch', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(
        coord,
        contains('ALWAYS clear the swap latch when skip ends'),
      );
      expect(coord, contains('_suppressTransientNotPlaying = false'));
    });

    test('pause always reaches audio pause — no debounce-only early return',
        () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> pause()');
      expect(idx, greaterThanOrEqualTo(0));
      final end = coord.indexOf('Future<void> dismissPlayer()', idx);
      final body = coord.substring(idx, end);
      expect(
        body.contains('if (!_acceptPlayPauseControl())'),
        isFalse,
        reason: 'Debounced pause left audio playing with a wrong icon.',
      );
      expect(body, contains('await _audio.pause()'));
      expect(body, contains('pausesPlayback: true'));
    });
  });
}
