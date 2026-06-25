import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/data/repositories/playlist_repository.dart';
import 'package:whisperback/domain/entities/audio_clip.dart';

/// Covers the exact path the client tried: record → play → delete → re-open
/// the add-clips screen. These assertions guard against regressions where
/// deleted clips reappear, file rows leak, or the SQLite delete partially
/// succeeds (the client's reported "deleted clips were there" scenario).
void main() {
  late DatabaseHelper db;
  late ClipRepository clips;
  late PlaylistRepository playlists;

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) await file.delete();
    clips = ClipRepository(db);
    playlists = PlaylistRepository(db);
    await db.database;
  });

  tearDown(() async {
    await db.close();
  });

  test('create then getAll returns the new clip', () async {
    final clip = await clips.create(
      title: 'Voice memo',
      filePath: '/tmp/test.m4a',
      durationMs: 12345,
      source: ClipSource.recorded,
    );

    final list = await clips.getAll();
    expect(list, hasLength(1));
    expect(list.single.id, clip.id);
    expect(list.single.title, 'Voice memo');
    expect(list.single.durationMs, 12345);
    expect(list.single.source, ClipSource.recorded);
  });

  test('delete removes the row from getAll on subsequent reads', () async {
    final clip = await clips.create(
      title: 'Temp',
      filePath: '/tmp/temp.m4a',
      durationMs: 1000,
      source: ClipSource.recorded,
    );
    expect((await clips.getAll()).length, 1);

    await clips.delete(clip.id);

    final after = await clips.getAll();
    expect(after, isEmpty,
        reason: 'After delete, the row must not reappear in getAll(). '
            'Regression here = client report "deleted clips were there".');
    expect(await clips.getById(clip.id), isNull);
  });

  test('delete also cascades the playlist_clips join row', () async {
    final clip = await clips.create(
      title: 'Hooked',
      filePath: '/tmp/hooked.m4a',
      durationMs: 5000,
      source: ClipSource.recorded,
    );
    final playlist = await playlists.create('Daily');
    await playlists.addClip(playlist.id, clip.id);
    expect((await playlists.getClips(playlist.id)).length, 1);

    await clips.delete(clip.id);

    final stillInPlaylist = await playlists.getClips(playlist.id);
    expect(stillInPlaylist, isEmpty,
        reason: 'Deleting a clip must purge join rows so the playlist '
            'detail screen never shows a dangling tile.');
  });

  test('delete is idempotent: re-deleting a missing id does not throw',
      () async {
    final clip = await clips.create(
      title: 'Once',
      filePath: '/tmp/once.m4a',
      durationMs: 1000,
      source: ClipSource.recorded,
    );
    await clips.delete(clip.id);
    await clips.delete(clip.id); // should not throw
    expect(await clips.getAll(), isEmpty);
  });

  test('getAll(source: imported) filters correctly', () async {
    await clips.create(
      title: 'rec',
      filePath: '/tmp/rec.m4a',
      durationMs: 1,
      source: ClipSource.recorded,
    );
    await clips.create(
      title: 'imp',
      filePath: '/tmp/imp.mp3',
      durationMs: 1,
      source: ClipSource.imported,
    );

    expect((await clips.getAll(source: ClipSource.recorded)).length, 1);
    expect((await clips.getAll(source: ClipSource.imported)).length, 1);
    expect((await clips.getAll()).length, 2);
  });

  test(
    'a fresh add-clips reload after a library delete sees the updated set',
    () async {
      // Reproduces the "click again on add clip and deleted clips were there"
      // client report — guarantees that re-querying `clipRepo.getAll()` after
      // a delete returns the up-to-date list, not stale data.
      final keep = await clips.create(
        title: 'Keep',
        filePath: '/tmp/k.m4a',
        durationMs: 1,
        source: ClipSource.recorded,
      );
      final drop = await clips.create(
        title: 'Drop',
        filePath: '/tmp/d.m4a',
        durationMs: 1,
        source: ClipSource.recorded,
      );

      // First load — both visible
      final firstLoad = await clips.getAll();
      expect(firstLoad.map((c) => c.id), containsAll([keep.id, drop.id]));

      // Delete one
      await clips.delete(drop.id);

      // Simulate the add-clips screen calling _load() again
      final secondLoad = await clips.getAll();
      expect(secondLoad.map((c) => c.id), contains(keep.id));
      expect(secondLoad.map((c) => c.id), isNot(contains(drop.id)));
    },
  );
}
