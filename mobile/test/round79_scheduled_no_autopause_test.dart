// Round 79 — scheduled native clips must not auto-pause mid-playlist.
//
// Root cause: a parked manual-preview ExoPlayer session left `_playingClip`
// true, so `suspendSilenceForExternalPlayback` returned early, the stale
// audio_service MediaSession stayed bound, and shade PAUSE echoed into
// `pauseNative()`. A leftover `_userInitiatedPause` latch also made the
// coordinator ignore native PLAYING ticks on the next schedule fire.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  final f = File(relative);
  if (!f.existsSync()) {
    fail('Expected source file missing: $relative');
  }
  return f.readAsStringSync();
}

void main() {
  group('Round 79 — scheduled playback must not auto-pause', () {
    test('build id stamped R79', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R79-scheduled-no-autopause'"));
    });

    test('native first fire clears parked manual pause latch', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('void _onNativePlaybackState(');
      expect(idx, greaterThan(0));
      final body = coord.substring(idx, (idx + 5500).clamp(0, coord.length));
      expect(body, contains('final firstStart = !_nativeScheduledActive'));
      expect(body, contains('if (firstStart)'));
      expect(body, contains('_userInitiatedPause = false'));
      expect(
        body.indexOf('_userInitiatedPause = false'),
        lessThan(body.indexOf('if (_userInitiatedPause)')),
        reason: 'Clear parked manual pause before ignoring native PLAYING ticks.',
      );
    });

    test('suspendSilence parks ExoPlayer instead of returning early', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> suspendSilenceForExternalPlayback()');
      expect(idx, greaterThan(0));
      final body = handler.substring(idx, (idx + 1200).clamp(0, handler.length));
      expect(body, contains('_parkClipForNativeTakeover'));
      expect(body, isNot(contains('if (_playingClip) return;')));
    });

    test('transport abort only pauseNative on explicit pause intent', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _abortInFlightTransport(');
      expect(idx, greaterThan(0));
      final body = coord.substring(idx, (idx + 900).clamp(0, coord.length));
      expect(body, contains('_latestTransportPausesPlayback'));
      expect(body, contains('pauseNative'));
    });

    test('notification pause ignores stale ExoPlayer session during native play', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      final idx = coord.indexOf('Future<void> _handleNotificationPause()');
      expect(idx, greaterThan(0));
      final body = coord.substring(idx, (idx + 900).clamp(0, coord.length));
      expect(body, contains('!_audio.isPlayingClip'));
      expect(body, contains('pauseNative'));
    });
  });
}
