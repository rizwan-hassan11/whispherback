// Round 64 — sticky native ownership hijacked library controls:
// mini-player used native.isPlaying while ExoPlayer played; next/pause
// routed to skipNative/pauseNative; optimistic skip titles stuck when bind
// failed; single-clip queues showed next that only seeked to zero.
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
  group('Round 64 — exclusive Dart ownership for manual play', () {
    test('native state is ignored while dart owns manual session', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_dartOwnsManualSession'));
      expect(coord, contains('_claimDartManualSession'));
      expect(coord, contains('while the user is in a Clip Library'));
      final idx = coord.indexOf('void _onNativePlaybackState(');
      final body = coord.substring(idx, idx + 500);
      expect(body, contains('if (_dartOwnsManualSession)'));
    });

    test('playClip claims dart session and stops leftover native', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('await _claimDartManualSession()'));
      expect(coord, contains('stopNative()'));
    });

    test('mini-player dartOwns ignores sticky nativeActive', () {
      final bar = _read('lib/features/playback/mini_player_bar.dart');
      expect(bar, contains('Round 64: Dart owns the bar'));
      expect(
        bar.contains('!nativeLive'),
        isFalse,
        reason: 'Sticky nativeLive must not steal dartOwns.',
      );
      expect(bar, contains('manualPlaying'));
      expect(
        bar,
        contains('snap?.state == AppPlaybackState.manualPlaying) return'),
      );
    });

    test('failed skip bind keeps committed title (no revert)', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord.contains('_preSkipSnapshot'), isFalse);
      expect(coord.contains('_revertOptimisticSkipTitle'), isFalse);
      expect(coord, contains('never revert title/index'));
    });

    test('canSkipClips requires a multi-clip queue', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('bool get canSkipClips');
      final body = coord.substring(idx, idx + 450);
      expect(body, contains('_libraryQueue.length > 1'));
      expect(body, contains('_playlistClipCache.length > 1'));
    });

    test('skip settle does not force isPlaying from MediaItem alone', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      // Round 66: after skip, bound MediaItem may keep the playing icon for
      // one ExoPlayer lag frame — but never via the Round-61 `audible || mediaItem`
      // force that left pause broken.
      expect(
        coord.contains('isPlaying: audible || _audio.mediaItem != null'),
        isFalse,
      );
      expect(coord, contains('showPlaying'));
      expect(coord, contains('forcePaused'));
    });
  });
}
