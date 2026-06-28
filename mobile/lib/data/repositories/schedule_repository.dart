import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/playback_schedule.dart';
import '../database/database_helper.dart';

class ScheduleConflictException implements Exception {
  ScheduleConflictException(
    this.existingPlaylistName, {
    this.suggestedStartTime,
  });
  final String existingPlaylistName;

  /// A nearby start time that does NOT conflict with the existing
  /// schedule (e.g. 2 minutes later than the user's pick). The UI can
  /// surface this in the conflict dialog as a one-tap "Use ${time}
  /// instead" action so the user is never stuck — every conflict has
  /// an obvious next step.
  final DateTime? suggestedStartTime;
}

class ScheduleRepository {
  ScheduleRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

  Future<List<PlaybackSchedule>> getAll() async {
    final db = await _db.database;
    // Include `playlist_duration_ms` so the schedule entity carries enough
    // info for `nextFireTime` to do interval-from-end math
    // (`completion + playlist_duration + interval`). The LEFT JOIN
    // returns 0 when the playlist has no clips, which falls back to the
    // old "interval from start" behaviour without crashing.
    final rows = await db.rawQuery('''
      SELECT s.*,
        p.name AS playlist_name,
        COALESCE((
          SELECT SUM(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS playlist_duration_ms
      FROM schedules s
      INNER JOIN playlists p ON p.id = s.playlist_id
      ORDER BY s.start_time ASC
    ''');
    return rows.map(_fromRow).toList();
  }

  Future<PlaybackSchedule?> getForPlaylist(String playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*,
        p.name AS playlist_name,
        COALESCE((
          SELECT SUM(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS playlist_duration_ms
      FROM schedules s
      INNER JOIN playlists p ON p.id = s.playlist_id
      WHERE s.playlist_id = ?
    ''',
      [
        playlistId,
      ],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<PlaybackSchedule> save({
    String? id,
    required String playlistId,
    required DateTime startTime,
    DateTime? endTime,
    required int intervalMinutes,
    bool shuffleEnabled = false,
    bool alarmEnabled = true,
    int daysMask = 127,
    bool? enabled,
  }) async {
    final db = await _db.database;
    final existing = await getAll();
    for (final other in existing) {
      if (other.playlistId == playlistId) continue;
      if (!other.enabled) continue;
      if (_wouldConflict(
        other,
        startTime: startTime,
        endTime: endTime,
        intervalMinutes: intervalMinutes,
        daysMask: daysMask,
      )) {
        final suggested = _suggestNonConflictingStart(
          requested: startTime,
          endTime: endTime,
          intervalMinutes: intervalMinutes,
          daysMask: daysMask,
          existing: existing
              .where((e) => e.playlistId != playlistId && e.enabled)
              .toList(),
        );
        throw ScheduleConflictException(
          other.playlistName,
          suggestedStartTime: suggested,
        );
      }
    }

    // Look up any existing row for this PLAYLIST (not by the caller's `id` —
    // the builder may have raced its async load and passed `null`, in which
    // case using the caller's id would generate a fresh UUID and skip the
    // preservation entirely). The schema has UNIQUE(playlist_id), so there
    // is at most one row to consider.
    final priorRows = await db.query(
      'schedules',
      columns: ['id', 'enabled'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    final priorRow = priorRows.isEmpty ? null : priorRows.first;
    // Reuse the existing row's id when the caller didn't supply one. This
    // keeps the schedule's stable identity across edits, which the engine
    // relies on for `_lastFired` / `_failureBackoff` keying.
    final scheduleId = id ?? (priorRow?['id'] as String?) ?? _uuid.v4();
    // CRITICAL: Preserve the existing `enabled` flag on edit/update. The
    // previous code always wrote `enabled: 1`, which silently re-enabled a
    // schedule that the user had explicitly toggled OFF in the overview —
    // and then the engine started firing it again "by itself" later. New
    // schedules (no prior row) default to enabled when the caller doesn't
    // specify; explicit `enabled:` from the caller wins in all cases.
    final bool resolvedEnabled;
    if (enabled != null) {
      resolvedEnabled = enabled;
    } else if (priorRow == null) {
      resolvedEnabled = true;
    } else {
      resolvedEnabled = (priorRow['enabled'] as int? ?? 1) == 1;
    }
    await db.insert(
      'schedules',
      {
        'id': scheduleId,
        'playlist_id': playlistId,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'interval_minutes': intervalMinutes,
        'shuffle_enabled': shuffleEnabled ? 1 : 0,
        'alarm_enabled': alarmEnabled ? 1 : 0,
        'days_mask': daysMask,
        'enabled': resolvedEnabled ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final rows = await db.rawQuery(
      '''
      SELECT s.*,
        p.name AS playlist_name,
        COALESCE((
          SELECT SUM(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS playlist_duration_ms
      FROM schedules s
      INNER JOIN playlists p ON p.id = s.playlist_id
      WHERE s.id = ?
    ''',
      [
        scheduleId,
      ],
    );
    return _fromRow(rows.first);
  }

  Future<void> remove(String playlistId) async {
    final db = await _db.database;
    await db
        .delete('schedules', where: 'playlist_id = ?', whereArgs: [playlistId]);
  }

  Future<void> setEnabled(String playlistId, bool enabled) async {
    final db = await _db.database;
    await db.update(
      'schedules',
      {'enabled': enabled ? 1 : 0},
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Returns true ONLY when two schedules collide on their FIRST slot of an
  /// overlapping day (i.e. their `startTime` is within 1 minute on a shared
  /// weekday). Previously this method compared every clock-grid slot of one
  /// schedule against every slot of the other and flagged any pair within
  /// 30 seconds as a conflict — so a 100-minute interval schedule generated
  /// ~15 slots per day and a 5-minute interval schedule generated ~288,
  /// producing 4320 pairs to test. The chance that ANY pair was within
  /// 30s was astronomically high even for schedules the user perceived as
  /// completely non-conflicting (the QA report "100-min interval + ANY
  /// interval → conflict error").
  ///
  /// The runtime engine (see `ScheduleEngine._slotTakenByOtherSchedule`)
  /// already dedups by exact `lastFired.slot` minute equality, so a real
  /// runtime collision cannot fire two playlists at the same instant. This
  /// pre-save check now only catches the OBVIOUS case where two users
  /// schedule the same start-time on the same days — a true UX-level
  /// duplication. Everything else is the engine's job at fire time.
  /// Walks forward 1 minute at a time (up to 4 hours) from [requested]
  /// looking for the first start time that does NOT conflict with any
  /// of [existing]. Returns null if every minute in the search window
  /// conflicts (extremely rare — would require dozens of competing
  /// schedules).
  DateTime? _suggestNonConflictingStart({
    required DateTime requested,
    required DateTime? endTime,
    required int intervalMinutes,
    required int daysMask,
    required List<PlaybackSchedule> existing,
  }) {
    for (var offsetMin = 1; offsetMin <= 240; offsetMin++) {
      final candidate = requested.add(Duration(minutes: offsetMin));
      final conflicts = existing.any((other) => _wouldConflict(
            other,
            startTime: candidate,
            endTime: endTime,
            intervalMinutes: intervalMinutes,
            daysMask: daysMask,
          ));
      if (!conflicts) return candidate;
    }
    return null;
  }

  bool _wouldConflict(
    PlaybackSchedule existing, {
    required DateTime startTime,
    required DateTime? endTime,
    required int intervalMinutes,
    required int daysMask,
  }) {
    if ((existing.daysMask & daysMask) == 0) return false;
    final existingStartMin =
        existing.startTime.hour * 60 + existing.startTime.minute;
    final newStartMin = startTime.hour * 60 + startTime.minute;
    final delta = (existingStartMin - newStartMin).abs();
    // 1-minute tolerance accounts for users who pick 9:00 vs 9:01 (clearly
    // a "different" schedule from their POV). Wider tolerance would
    // generate the false-positive QA reports.
    return delta < 1;
  }

  PlaybackSchedule _fromRow(Map<String, Object?> row) {
    final endRaw = row['end_time'] as String?;
    // `playlist_duration_ms` can come back as either int (sqflite Android)
    // or num (sqflite_common) depending on platform; coerce to int.
    final rawDuration = row['playlist_duration_ms'];
    final durationMs = rawDuration is int
        ? rawDuration
        : (rawDuration is num ? rawDuration.toInt() : 0);
    return PlaybackSchedule(
      id: row['id']! as String,
      playlistId: row['playlist_id']! as String,
      startTime: DateTime.parse(row['start_time']! as String),
      endTime: endRaw != null ? DateTime.parse(endRaw) : null,
      intervalMinutes: row['interval_minutes']! as int,
      shuffleEnabled: (row['shuffle_enabled'] as int) == 1,
      alarmEnabled: (row['alarm_enabled'] as int?) != 0,
      daysMask: row['days_mask'] as int? ?? 127,
      enabled: (row['enabled'] as int) == 1,
      playlistName: row['playlist_name']! as String,
      playlistDurationMs: durationMs,
    );
  }
}
