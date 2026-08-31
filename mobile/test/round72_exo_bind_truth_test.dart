// Round 72 — next/prev must change ExoPlayer source, not only MediaItem title.
// Round 71 publishPendingClip set MediaItem.id before bind; failed/raced
// playFile then "recovered" via resume() because mediaItem.id already matched.
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
  group('Round 72 — title follows exo bind truth', () {
    test('playFile success requires exoBoundPath, not MediaItem.id', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      expect(handler, contains('String? _exoBoundPath'));
      expect(handler, contains('_exoBoundPath = path'));
      expect(handler, contains('if (!isExoBoundTo(path)) return false'));
      expect(
        handler.contains('if (mediaItem.value?.id != path) return false'),
        isFalse,
      );
    });

    test('publishPendingClip keeps prior MediaItem.id until bind', () {
      final handler = _read('lib/services/audio/whisper_audio_handler.dart');
      final idx = handler.indexOf('void publishPendingClip(');
      final end = handler.indexOf('MediaItem _clipMediaItem(', idx);
      final body = handler.substring(idx, end);
      expect(body, contains('current.copyWith('));
      expect(body, contains('Keep the bound file id until playFile rebinds'));
      expect(body.contains('_exoBoundPath = path'), isFalse);
    });

    test('publishPendingClip does not set currentPath early', () {
      final audio = _read('lib/services/audio/audio_services.dart');
      final idx = audio.indexOf('void publishPendingClip(');
      final end = audio.indexOf('void restoreCurrentPath(', idx);
      final body = audio.substring(idx, end);
      expect(body.contains('_currentPath = path'), isFalse);
      expect(audio, contains('boundPath => _handler.exoBoundPath'));
    });

    test('skip recovery never resumes on optimistic MediaItem.id', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('_audio.isExoBoundTo(clip.filePath)'));
      expect(
        coord.contains('_audio.mediaItem?.id == clip.filePath'),
        isFalse,
      );
      expect(
        coord.contains('_audio.boundPath == clip.filePath ||'),
        isFalse,
      );
    });

    test('skip force-binds when exo is behind committed queue path', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains('force-bind committed path'));
      expect(coord, contains('!_audio.isExoBoundTo(wantPath)'));
    });

    test('build id stamped R72', () {
      final coord = _read('lib/services/playback/playback_coordinator.dart');
      expect(coord, contains("transportBuildId = 'R78-notif-transport'"));
    });
  });
}
