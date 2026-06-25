import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../../domain/entities/playlist.dart';
import '../database/database_helper.dart';

/// Thrown when creating a playlist would exceed the tier limit.
class PlaylistLimitException implements Exception {
  const PlaylistLimitException(this.limit);
  final int limit;
}

/// Thrown when a playlist name collides with an existing one. The repository
/// converts the raw SQLite `UNIQUE` constraint failure into a typed error so
/// the UI can show a friendly "name already used" message instead of crashing.
class DuplicatePlaylistNameException implements Exception {
  const DuplicatePlaylistNameException(this.name);
  final String name;
  @override
  String toString() => 'Playlist name "$name" is already in use.';
}

class PlaylistRepository {
  PlaylistRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

  /// Tier caps (Phase 1 is offline → Basic). Premium unlocks 50 in Phase 2.
  static const int basicLimit = 20;
  static const int premiumLimit = 50;

  Future<int> count() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM playlists');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Playlist>> getAll() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
        COUNT(pc.clip_id) AS clip_count,
        COALESCE(SUM(c.duration_ms), 0) AS total_duration_ms,
        CASE WHEN s.id IS NOT NULL THEN 1 ELSE 0 END AS has_schedule
      FROM playlists p
      LEFT JOIN playlist_clips pc ON pc.playlist_id = p.id
      LEFT JOIN clips c ON c.id = pc.clip_id
      LEFT JOIN schedules s ON s.playlist_id = p.id AND s.enabled = 1
      GROUP BY p.id
      ORDER BY p.updated_at DESC
    ''');
    return rows.map(_fromRow).toList();
  }

  Future<Playlist?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<AudioClip>> getClips(String playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.* FROM clips c
      INNER JOIN playlist_clips pc ON pc.clip_id = c.id
      WHERE pc.playlist_id = ?
      ORDER BY pc.sort_order ASC
    ''',
      [
        playlistId,
      ],
    );
    return rows.map((row) {
      return AudioClip(
        id: row['id']! as String,
        title: row['title']! as String,
        filePath: row['file_path']! as String,
        durationMs: row['duration_ms']! as int,
        createdAt: DateTime.parse(row['created_at']! as String),
        source: ClipSource.values.byName(row['source']! as String),
      );
    }).toList();
  }

  Future<Playlist> create(String name) async {
    if (await count() >= basicLimit) {
      throw const PlaylistLimitException(basicLimit);
    }
    final now = DateTime.now();
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    try {
      await db.insert('playlists', {
        'id': playlist.id,
        'name': playlist.name,
        'created_at': playlist.createdAt.toIso8601String(),
        'updated_at': playlist.updatedAt.toIso8601String(),
        'shuffle_enabled': 0,
      });
    } on DatabaseException catch (e) {
      // SQLite `UNIQUE constraint failed: playlists.name` — translate to a
      // typed error so the UI can render a friendly toast instead of
      // bubbling a raw plugin exception that looks like a crash to users.
      if (e.isUniqueConstraintError()) {
        throw DuplicatePlaylistNameException(name);
      }
      rethrow;
    }
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    final db = await _db.database;
    try {
      await db.update(
        'playlists',
        {'name': name, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DuplicatePlaylistNameException(name);
      }
      rethrow;
    }
  }

  Future<void> setShuffle(String id, bool enabled) async {
    final db = await _db.database;
    await db.update(
      'playlists',
      {
        'shuffle_enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addClip(String playlistId, String clipId) async {
    final db = await _db.database;
    // Wrap the count + insert + timestamp update in a transaction so two
    // concurrent adds can't both compute the same `sort_order` and end up
    // with duplicate ordering values. Use `INSERT OR IGNORE` so re-adding a
    // clip that's already in the playlist is a quiet no-op instead of a PK
    // violation — the Add Clips sheet relies on this safety net when a
    // user double-taps or two screens race.
    await db.transaction((txn) async {
      final existing = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM playlist_clips '
              'WHERE playlist_id = ? AND clip_id = ?',
              [playlistId, clipId],
            ),
          ) ??
          0;
      if (existing > 0) {
        // Already present — touch updated_at so the list view still sorts
        // this playlist to the top.
        await txn.update(
          'playlists',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
        return;
      }
      final count = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM playlist_clips WHERE playlist_id = ?',
              [playlistId],
            ),
          ) ??
          0;
      await txn.insert(
        'playlist_clips',
        {
          'playlist_id': playlistId,
          'clip_id': clipId,
          'sort_order': count,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'playlists',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  Future<void> removeClip(String playlistId, String clipId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_clips',
        where: 'playlist_id = ? AND clip_id = ?',
        whereArgs: [playlistId, clipId],
      );
      // Keep `updated_at` fresh so the list view reflects the edit.
      await txn.update(
        'playlists',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  /// Persists a new play order for clips in a playlist.
  Future<void> reorderClips(String playlistId, List<String> clipIds) async {
    final db = await _db.database;
    final batch = db.batch();
    for (var i = 0; i < clipIds.length; i++) {
      batch.update(
        'playlist_clips',
        {'sort_order': i},
        where: 'playlist_id = ? AND clip_id = ?',
        whereArgs: [playlistId, clipIds[i]],
      );
    }
    await batch.commit(noResult: true);
    await db.update(
      'playlists',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<bool> delete(String id) async {
    final db = await _db.database;
    final schedule = await db.query(
      'schedules',
      where: 'playlist_id = ? AND enabled = 1',
      whereArgs: [id],
    );
    if (schedule.isNotEmpty) return false;
    // Atomic delete: if any step fails the entire delete rolls back so we
    // never end up with `playlist_clips` rows pointing at a missing playlist
    // (orphaned join rows blow up `getClips` later).
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_clips',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'schedules',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      await txn.delete('playlists', where: 'id = ?', whereArgs: [id]);
    });
    return true;
  }

  Playlist _fromRow(Map<String, Object?> row) {
    return Playlist(
      id: row['id']! as String,
      name: row['name']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      shuffleEnabled: (row['shuffle_enabled'] as int) == 1,
      clipCount: row['clip_count'] as int? ?? 0,
      totalDurationMs: row['total_duration_ms'] as int? ?? 0,
      hasSchedule: (row['has_schedule'] as int? ?? 0) == 1,
    );
  }
}
