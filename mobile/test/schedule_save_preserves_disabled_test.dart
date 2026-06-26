// Regression test for QA report:
//
//   "Initially the schedule worked perfectly, then I turned the schedule OFF,
//    but after some time the app started playing clips by itself. This
//    happened twice."
//
// Root cause: `ScheduleRepository.save()` always wrote `enabled: 1` to the
// row, even when the caller was just resaving an already-disabled schedule
// (e.g. the user edited the interval, or simply tapped Save again from the
// builder). The disabled state silently flipped back to enabled and the
// engine started firing the schedule.
//
// The fix: `save()` preserves the prior `enabled` value when the caller
// doesn't pass an explicit `enabled:` argument. New schedules still default
// to enabled. Tests below pin both contracts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whisperback/data/database/database_helper.dart';
import 'package:whisperback/data/repositories/playlist_repository.dart';
import 'package:whisperback/data/repositories/schedule_repository.dart';

void main() {
  late DatabaseHelper db;
  late PlaylistRepository playlists;
  late ScheduleRepository schedules;

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    final file = File(p.join(dbPath, 'whisperback.db'));
    if (await file.exists()) await file.delete();
    playlists = PlaylistRepository(db);
    schedules = ScheduleRepository(db);
    await db.database;
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'resaving an already-disabled schedule MUST NOT silently re-enable it',
    () async {
      final playlist = await playlists.create('Calm');
      final start = DateTime(2026, 5, 30, 9, 0);

      // 1. User creates a schedule — defaults to enabled.
      final initial = await schedules.save(
        playlistId: playlist.id,
        startTime: start,
        intervalMinutes: 10,
      );
      expect(initial.enabled, isTrue);

      // 2. User toggles it OFF from the overview screen.
      await schedules.setEnabled(playlist.id, false);
      final afterToggle = await schedules.getForPlaylist(playlist.id);
      expect(afterToggle!.enabled, isFalse,
          reason: 'sanity: the toggle must actually persist');

      // 3. User opens the builder for that playlist and taps Save (e.g.
      //    they changed the interval to 15 minutes, or just confirmed
      //    the existing values without realising the toggle would flip).
      //    The builder calls `save()` with the SAME id but does not pass
      //    an explicit `enabled:` argument.
      final resaved = await schedules.save(
        id: initial.id,
        playlistId: playlist.id,
        startTime: start,
        intervalMinutes: 15,
      );

      expect(resaved.enabled, isFalse,
          reason: 'Re-saving an existing disabled schedule must preserve '
              'the disabled flag. This is the exact path that caused the QA '
              'report — the schedule silently re-enabled itself and the '
              'engine started firing whispers the user explicitly stopped.');

      final reread = await schedules.getForPlaylist(playlist.id);
      expect(reread!.enabled, isFalse,
          reason: 'The DB row must agree with the returned model.');
      expect(reread.intervalMinutes, 15,
          reason: 'The other fields the user just edited must still take '
              'effect — preserving `enabled` is not "ignore the save".');
    },
  );

  test(
    'creating a NEW schedule still defaults to enabled when no flag is given',
    () async {
      final playlist = await playlists.create('New playlist');
      final created = await schedules.save(
        playlistId: playlist.id,
        startTime: DateTime(2026, 5, 30, 10, 0),
        intervalMinutes: 5,
      );
      expect(created.enabled, isTrue,
          reason: 'Brand-new schedules must default to enabled; we only '
              'preserve the prior value when a row already exists.');
    },
  );

  test(
    'passing explicit enabled: false on update is honoured (caller can still '
    'override the preserved value)',
    () async {
      final playlist = await playlists.create('Override-me');
      final start = DateTime(2026, 5, 30, 11, 0);
      final first = await schedules.save(
        playlistId: playlist.id,
        startTime: start,
        intervalMinutes: 5,
      );
      expect(first.enabled, isTrue);

      final updated = await schedules.save(
        id: first.id,
        playlistId: playlist.id,
        startTime: start,
        intervalMinutes: 5,
        enabled: false,
      );
      expect(updated.enabled, isFalse);
    },
  );
}
