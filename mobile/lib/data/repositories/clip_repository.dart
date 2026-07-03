import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../database/database_helper.dart';

class ClipRepository {
  ClipRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

  /// Round 24 — native duration probe channel (backed by
  /// `MediaMetadataRetriever` on Android). Only used when running on a
  /// device; unit tests fall back to the just_audio path which is
  /// stubbed in the test harness.
  static const MethodChannel _metadataChannel =
      MethodChannel('com.whisperback.clip_metadata');

  /// Round 24 — fires whenever `backfillDuration` writes a real
  /// duration to a clip row. UI providers subscribe so the tile
  /// re-renders with the real length instead of the placeholder 0:00.
  /// Kept as a broadcast stream so multiple consumers (clips list,
  /// playlist detail, add-clips sheet) can all watch without stepping
  /// on each other.
  static final StreamController<String> _durationBackfilledController =
      StreamController<String>.broadcast();
  static Stream<String> get onDurationBackfilled =>
      _durationBackfilledController.stream;

  @visibleForTesting
  static void debugEmitDurationBackfilled(String clipId) {
    if (!_durationBackfilledController.isClosed) {
      _durationBackfilledController.add(clipId);
    }
  }

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

  /// Best-effort, OFF-SESSION duration probe.
  ///
  /// Round 24 — TRIES the native `MediaMetadataRetriever` first (which
  /// reads the container header directly, no `MediaPlayer` involved),
  /// then falls back to `just_audio` if the channel is missing (non-
  /// Android, unit tests). The prior implementation was `just_audio`
  /// only, which on Samsung One UI 12+ intermittently returned null or
  /// timed out — that was the user's QA "clip card only shows 0:00
  /// instead of the actual length" symptom.
  ///
  /// On success, updates the row AND fires [onDurationBackfilled] so
  /// the UI providers can invalidate their cached list and re-render
  /// the tile with the real length. Prior to Round 24, nothing
  /// notified the UI after the backfill finished, so the placeholder
  /// 0:00 stayed until the user pulled to refresh or left+returned.
  ///
  /// Why this is safe vs. the old in-line probe in `audio_services.dart`:
  ///
  ///   * Runs on a microtask AFTER the DB row is committed, never during
  ///     the user's record/import gesture, so a Samsung quirk that auto-
  ///     starts the probe player no longer collides with the user's next
  ///     `playClip` tap (which was the "first recorded clip won't play"
  ///     reproduction recipe).
  ///   * Native probe never touches AudioSession / AudioManager, so it
  ///     can't consume audio focus even in principle.
  ///   * Fallback path wraps everything in try/catch and disposes the
  ///     player even on error so a corrupt file can't leak the native
  ///     MediaPlayer.
  Future<void> backfillDuration(String clipId, String filePath) async {
    // ── Primary path: native MediaMetadataRetriever. No AudioSession,
    // no MediaPlayer, no focus contention. Reliable on every device
    // we've tested (Samsung / Xiaomi / Vivo / Pixel).
    if (!kIsWeb) {
      try {
        final raw = await _metadataChannel.invokeMethod<Object?>(
          'readDurationMs',
          filePath,
        );
        final ms = _asInt(raw);
        if (ms > 0) {
          await updateDuration(clipId, ms);
          if (!_durationBackfilledController.isClosed) {
            _durationBackfilledController.add(clipId);
          }
          return;
        }
      } on MissingPluginException {
        // Non-Android / test environment: fall through to just_audio.
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'ClipRepository.backfillDuration native probe failed '
            '($clipId): $e',
          );
        }
        // Fall through to just_audio as a secondary attempt.
      }
    }

    // ── Fallback path: just_audio. Only reached when the native probe
    // is unavailable (unit tests, iOS/desktop, or missing plugin) or
    // returned 0 (unrecognised container).
    AudioPlayer? probe;
    try {
      probe = AudioPlayer();
      // Yield the event loop so the DB transaction has fully committed and
      // the foreground audio session (if any) has settled before we touch
      // the player at all. This is the order-of-operations bug that made
      // probing-during-import unsafe.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final duration =
          await probe.setFilePath(filePath).timeout(const Duration(seconds: 5));
      if (duration != null && duration.inMilliseconds > 0) {
        await updateDuration(clipId, duration.inMilliseconds);
        if (!_durationBackfilledController.isClosed) {
          _durationBackfilledController.add(clipId);
        }
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

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
