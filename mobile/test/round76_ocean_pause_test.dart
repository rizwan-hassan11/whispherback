// Round 76 — notification pause must stick against OEM audio-focus
// restore and late MediaSession PLAY echoes.
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
  group('Round 76 — notification pause sticks (ocean branding)', () {
    test('interruption restore never resumes while user-paused', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('!_userPausedClip'));
      expect(
        handler,
        contains('_wasPlayingBeforeInterruption = false'),
      );
      final pauseIdx = handler.indexOf('Future<void> pause() async');
      final pauseEnd = handler.indexOf('Future<void> seek(', pauseIdx);
      final pauseBody = handler.substring(pauseIdx, pauseEnd);
      expect(
        pauseBody,
        contains('_wasPlayingBeforeInterruption = false'),
        reason: 'User pause must clear the focus-restore arm.',
      );
    });

    test('broadcastState force-pauses if OEM resumed under latch', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('void _broadcastState(');
      final end = handler.indexOf('static const _stopControl', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('if (_userPausedClip)'));
      expect(body, contains('unawaited(_player.pause())'));
    });

    test('ensureAudible respects user-pause latch', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('Future<void> _ensureAudible(');
      final end = handler.indexOf('Future<void> _playFileBound(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('_invalidateForPause || _userPausedClip'));
    });

    test('oceanic brand colors + wordmark exist', () {
      final colors = _read('lib/core/theme/app_colors.dart');
      expect(colors, contains('0xFF0A2A43'));
      expect(colors, contains('0xFF5DD5E8'));
      expect(colors, contains('wordmarkBackDark'));
      expect(
        File(p.join(Directory.current.path, 'lib/core/widgets/whisper_wordmark.dart'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(Directory.current.path, 'assets/branding/app_logo.png'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(Directory.current.path, 'assets/branding/logo_mark.svg'))
            .existsSync(),
        isTrue,
      );
    });

    test('build id stamped R76', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R76-ocean-pause'"));
    });
  });
}
