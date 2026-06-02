import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../../domain/entities/playlist.dart';
import '../database/database_helper.dart';

class PlaylistRepository {
  PlaylistRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

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
    final now = DateTime.now();
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.insert('playlists', {
      'id': playlist.id,
      'name': playlist.name,
      'created_at': playlist.createdAt.toIso8601String(),
      'updated_at': playlist.updatedAt.toIso8601String(),
      'shuffle_enabled': 0,
    });
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    final db = await _db.database;
    await db.update(
      'playlists',
      {'name': name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM playlist_clips WHERE playlist_id = ?',
            [
              playlistId,
            ],
          ),
        ) ??
        0;
    await db.insert('playlist_clips', {
      'playlist_id': playlistId,
      'clip_id': clipId,
      'sort_order': count,
    });
    await db.update(
      'playlists',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> removeClip(String playlistId, String clipId) async {
    final db = await _db.database;
    await db.delete(
      'playlist_clips',
      where: 'playlist_id = ? AND clip_id = ?',
      whereArgs: [playlistId, clipId],
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
    await db
        .delete('playlist_clips', where: 'playlist_id = ?', whereArgs: [id]);
    await db.delete('schedules', where: 'playlist_id = ?', whereArgs: [id]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
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
