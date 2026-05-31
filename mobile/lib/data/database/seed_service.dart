import '../../domain/entities/audio_clip.dart';
import '../repositories/clip_repository.dart';
import '../repositories/playlist_repository.dart';
import 'database_helper.dart';

/// Seeds demo data on first launch for UI walkthrough.
class SeedService {
  static Future<void> seedIfEmpty() async {
    final db = DatabaseHelper.instance;
    final playlistRepo = PlaylistRepository(db);
    final clipRepo = ClipRepository(db);

    final playlists = await playlistRepo.getAll();
    if (playlists.isNotEmpty) return;

    final demoClips = <AudioClip>[
      await clipRepo.create(
        title: 'Morning affirmation',
        filePath: 'demo://seed/morning.m4a',
        durationMs: 45000,
        source: ClipSource.recorded,
      ),
      await clipRepo.create(
        title: 'Focus reminder',
        filePath: 'demo://seed/focus.m4a',
        durationMs: 30000,
        source: ClipSource.imported,
      ),
      await clipRepo.create(
        title: 'Evening gratitude',
        filePath: 'demo://seed/evening.m4a',
        durationMs: 60000,
        source: ClipSource.recorded,
      ),
    ];

    final morning = await playlistRepo.create('Morning Whispers');
    final focus = await playlistRepo.create('Work Focus');

    for (final clip in demoClips.take(2)) {
      await playlistRepo.addClip(morning.id, clip.id);
    }
    await playlistRepo.addClip(focus.id, demoClips[1].id);
    await playlistRepo.addClip(focus.id, demoClips[2].id);
  }
}
