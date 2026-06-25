import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../database/database_helper.dart';

class ClipRepository {
  ClipRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

  Future<List<AudioClip>> getAll({ClipSource? source}) async {
    final db = await _db.database;
    final rows = await db.query(
      'clips',
      orderBy: 'created_at DESC',
      where: source != null ? 'source = ?' : null,
      whereArgs: source != null ? [source.name] : null,
    );
    return rows.map(_fromRow).toList();
  }

  Future<AudioClip?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('clips', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<AudioClip> create({
    required String title,
    required String filePath,
    required int durationMs,
    required ClipSource source,
  }) async {
    final clip = AudioClip(
      id: _uuid.v4(),
      title: title,
      filePath: filePath,
      durationMs: durationMs,
      createdAt: DateTime.now(),
      source: source,
    );
    final db = await _db.database;
    await db.insert('clips', _toRow(clip));
    return clip;
  }

  Future<void> delete(String id) async {
    final clip = await getById(id);
    final db = await _db.database;
    // Atomic DB delete: the join-table cleanup and the clips row must succeed
    // or fail together so we never end up with a `playlist_clips` row that
    // joins to a missing clip (would crash `getClips` for the playlist).
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_clips',
        where: 'clip_id = ?',
        whereArgs: [id],
      );
      await txn.delete('clips', where: 'id = ?', whereArgs: [id]);
    });
    if (clip != null) {
      try {
        final file = File(clip.filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // File delete is best-effort. If it fails (file locked by another
        // reader, FS error), the orphan-file sweep on next bootstrap will
        // clean it up. We don't want a stuck file to block the DB delete.
      }
    }
  }

  AudioClip _fromRow(Map<String, Object?> row) {
    return AudioClip(
      id: row['id']! as String,
      title: row['title']! as String,
      filePath: row['file_path']! as String,
      durationMs: row['duration_ms']! as int,
      createdAt: DateTime.parse(row['created_at']! as String),
      source: ClipSource.values.byName(row['source']! as String),
    );
  }

  Map<String, Object?> _toRow(AudioClip clip) {
    return {
      'id': clip.id,
      'title': clip.title,
      'file_path': clip.filePath,
      'duration_ms': clip.durationMs,
      'created_at': clip.createdAt.toIso8601String(),
      'source': clip.source.name,
    };
  }
}
