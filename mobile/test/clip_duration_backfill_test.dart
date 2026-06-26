// Tests `ClipRepository.updateDuration` — the SQL half of the lazy
// duration backfill that replaced the dangerous in-line probe player.
// `backfillDuration` itself spins up `AudioPlayer`, which we can't do in
// the pure-VM test suite without the Android plugin runtime; the half
// we CAN test is the DB update, which we pin here so the repository
// contract is locked in.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/clip_repository.dart';
import 'package:whisperback/domain/entities/audio_clip.dart';

void main() {
  late DatabaseHelper helper;
  late ClipRepository repo;

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) await file.delete();
    repo = ClipRepository(helper);
    await helper.database;
  });

  tearDown(() async {
    await helper.close();
  });

  test('updateDuration overwrites a 0 duration written by import/record',
      () async {
    final created = await repo.create(
      title: 'New import',
      filePath: '/tmp/clip.m4a',
      durationMs: 0,
      source: ClipSource.imported,
    );
    expect(created.durationMs, 0,
        reason: 'import/record commit a 0 duration; the lazy backfill is '
            'the ONLY place that should fill the real value');

    await repo.updateDuration(created.id, 4321);

    final reloaded = await repo.getById(created.id);
    expect(reloaded?.durationMs, 4321);
  });

  test('updateDuration is a silent no-op for unknown ids', () async {
    // Backfill races with delete on the device — the user may delete the
    // clip between the row commit and the duration probe completing. The
    // update must NOT throw or recreate the row.
    await repo.updateDuration('does-not-exist', 9999);
    final all = await repo.getAll();
    expect(all, isEmpty);
  });

  test(
      'create() accepts durationMs:0 (the new contract after the in-line '
      'probe was removed)', () async {
    // Pin the contract: import & record now always insert with 0; the
    // backfill fills it in later. If a future refactor reintroduces a
    // probe and the probe throws, we must still end up with a usable row
    // — this test guarantees create() doesn't reject 0.
    final clip = await repo.create(
      title: 'Bare clip',
      filePath: '/tmp/bare.m4a',
      durationMs: 0,
      source: ClipSource.recorded,
    );
    expect(clip.durationMs, 0);
    expect(clip.id, isNotEmpty);
  });
}
