import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
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

  /// Updates [duration_ms] on an existing clip row. Used by the lazy
  /// duration backfill triggered after import/record so the in-memory
  /// snapshot the UI shows next time picks up the real length.
  Future<void> updateDuration(String id, int durationMs) async {
    final db = await _db.database;
    await db.update(
      'clips',
      {'duration_ms': durationMs},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Best-effort, OFF-SESSION duration probe. Spawns an isolated
  /// `AudioPlayer`, reads the duration, disposes — and crucially, NEVER
  /// calls `play()` and NEVER touches the shared `AudioSession`. Failure is
  /// silent: the clip stays playable, only the length badge stays at 0:00.
  ///
  /// Why this is safe vs. the old in-line probe in `audio_services.dart`:
  ///
  ///   * Runs on a microtask AFTER the DB row is committed, never during
  ///     the user's record/import gesture, so a Samsung quirk that auto-
  ///     starts the probe player no longer collides with the user's next
  ///     `playClip` tap (which was the "first recorded clip won't play"
  ///     reproduction recipe).
  ///   * Wraps everything in try/catch and disposes the player even on
  ///     error so a corrupt file can't leak the native MediaPlayer.
  ///   * No `setActive`, no source mutation on the global player.
  Future<void> backfillDuration(String clipId, String filePath) async {
    AudioPlayer? probe;
    try {
      probe = AudioPlayer();
      // Yield the event loop so the DB transaction has fully committed and
      // the foreground audio session (if any) has settled before we touch
      // the player at all. This is the order-of-operations bug that made
      // probing-during-import unsafe.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final duration = await probe
          .setFilePath(filePath)
          .timeout(const Duration(seconds: 5));
      if (duration != null && duration.inMilliseconds > 0) {
        await updateDuration(clipId, duration.inMilliseconds);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ClipRepository.backfillDuration($clipId) failed: $e');
      }
    } finally {
      try {
        await probe?.dispose();
      } catch (_) {}
    }
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
