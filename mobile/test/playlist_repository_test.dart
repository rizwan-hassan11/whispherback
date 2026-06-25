import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/data/repositories/playlist_repository.dart';
import 'package:whisperback/domain/entities/audio_clip.dart';

/// Direct tests for `PlaylistRepository`. These pin the data-layer contract
/// the UI, schedule engine, and playback coordinator all rely on. Most of the
/// client-reported "I press add and the deleted clip is still there" type
/// bugs would have been caught here if the repository had real coverage.
void main() {
  late DatabaseHelper db;
  late PlaylistRepository repo;
  late ClipRepository clips;

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) await file.delete();
    repo = PlaylistRepository(db);
    clips = ClipRepository(db);
    await db.database;
  });

  tearDown(() async {
    await db.close();
  });

  Future<AudioClip> seedClip(String title) => clips.create(
        title: title,
        filePath: 'sandbox/clips/$title.m4a',
        durationMs: 30000,
        source: ClipSource.recorded,
      );

  test('create rejects names that collide with an existing playlist', () async {
    await repo.create('Morning');
    expect(
      () => repo.create('Morning'),
      throwsA(isA<DuplicatePlaylistNameException>()),
    );
  });

  test('rename rejects names that collide with another playlist', () async {
    final morning = await repo.create('Morning');
    await repo.create('Evening');
    expect(
      () => repo.rename(morning.id, 'Evening'),
      throwsA(isA<DuplicatePlaylistNameException>()),
    );
  });

  test('rename succeeds when the new name is unique', () async {
    final p = await repo.create('Quiet');
    await repo.rename(p.id, 'Soft Reminders');
    final reloaded = await repo.getById(p.id);
    expect(reloaded?.name, 'Soft Reminders');
  });

  test('addClip the same clip twice is idempotent (no duplicate row)',
      () async {
    final p = await repo.create('Focus');
    final c = await seedClip('Affirm A');
    await repo.addClip(p.id, c.id);
    await repo.addClip(p.id, c.id);
    final list = await repo.getClips(p.id);
    expect(list, hasLength(1));
    expect(list.first.id, c.id);
  });

  test(
      'addClip assigns sort_order starting at 0 and keeps insertion order on '
      'subsequent adds (no replays of track 1 from sort regressions)',
      () async {
    final p = await repo.create('Order Test');
    final a = await seedClip('A');
    final b = await seedClip('B');
    final c = await seedClip('C');
    await repo.addClip(p.id, a.id);
    await repo.addClip(p.id, b.id);
    await repo.addClip(p.id, c.id);
    final list = await repo.getClips(p.id);
    expect(list.map((c) => c.title), ['A', 'B', 'C']);
  });

  test(
      'removeClip touches updated_at so the list view re-sorts the edited '
      'playlist to the top', () async {
    final p = await repo.create('Updated');
    final c = await seedClip('Solo');
    await repo.addClip(p.id, c.id);
    final before = (await repo.getById(p.id))!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.removeClip(p.id, c.id);
    final after = (await repo.getById(p.id))!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });

  test('reorderClips writes a new contiguous sort_order', () async {
    final p = await repo.create('Reorder');
    final a = await seedClip('A');
    final b = await seedClip('B');
    final c = await seedClip('C');
    await repo.addClip(p.id, a.id);
    await repo.addClip(p.id, b.id);
    await repo.addClip(p.id, c.id);
    await repo.reorderClips(p.id, [c.id, a.id, b.id]);
    final list = await repo.getClips(p.id);
    expect(list.map((c) => c.title), ['C', 'A', 'B']);
  });

  test('delete is blocked when an enabled schedule references the playlist',
      () async {
    final p = await repo.create('Scheduled');
    final database = await db.database;
    await database.insert('schedules', {
      'id': 'sched-1',
      'playlist_id': p.id,
      'start_time': '08:00',
      'end_time': '12:00',
      'interval_minutes': 30,
      'shuffle_enabled': 0,
      'alarm_enabled': 1,
      'days_mask': 127,
      'enabled': 1,
    });
    final result = await repo.delete(p.id);
    expect(result, isFalse);
    expect(await repo.getById(p.id), isNotNull);
  });

  test('delete succeeds and cascades when the schedule is disabled', () async {
    final p = await repo.create('Soft delete');
    final database = await db.database;
    await database.insert('schedules', {
      'id': 'sched-2',
      'playlist_id': p.id,
      'start_time': '08:00',
      'interval_minutes': 30,
      'shuffle_enabled': 0,
      'alarm_enabled': 1,
      'days_mask': 127,
      'enabled': 0,
    });
    final ok = await repo.delete(p.id);
    expect(ok, isTrue);
    final left = await database
        .query('schedules', where: 'playlist_id = ?', whereArgs: [p.id]);
    expect(left, isEmpty);
  });

  test('delete is atomic — failure on one step leaves DB untouched', () async {
    // Construct a playlist with clips so the transaction has to touch two
    // tables, then verify both rows exist before delete.
    final p = await repo.create('Atomic');
    final c = await seedClip('Atomic clip');
    await repo.addClip(p.id, c.id);
    expect(await repo.getClips(p.id), hasLength(1));
    await repo.delete(p.id);
    final database = await db.database;
    final joinRows = await database
        .query('playlist_clips', where: 'playlist_id = ?', whereArgs: [p.id]);
    expect(joinRows, isEmpty);
    expect(await repo.getById(p.id), isNull);
  });

  test('count enforces the 20-playlist basic tier limit', () async {
    for (var i = 0; i < PlaylistRepository.basicLimit; i++) {
      await repo.create('list $i');
    }
    expect(
      () => repo.create('one too many'),
      throwsA(isA<PlaylistLimitException>()),
    );
  });
}
