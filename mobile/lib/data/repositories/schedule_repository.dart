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
    // info for `nextFireTime`'s `effectiveStep` math
    // (`max(playlist_duration, interval)`, start-to-start). The LEFT JOIN
    // returns 0 when the playlist has no clips, which falls back to the
    // 60s duration floor without crashing.
    final rows = await db.rawQuery('''
      SELECT s.*,
        p.name AS playlist_name,
        COALESCE((
          SELECT SUM(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS playlist_duration_ms,
        COALESCE((
          SELECT MAX(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS max_clip_duration_ms
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
        ), 0) AS playlist_duration_ms,
        COALESCE((
          SELECT MAX(c.duration_ms)
          FROM playlist_clips pc
          INNER JOIN clips c ON c.id = pc.clip_id
          WHERE pc.playlist_id = s.playlist_id
        ), 0) AS max_clip_duration_ms
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
    // Compute THIS playlist's total duration so the conflict check can
    // model the new schedule's active windows correctly.
    final durationRows = await db.rawQuery('''
      SELECT COALESCE(SUM(c.duration_ms), 0) AS total,
             COALESCE(MAX(c.duration_ms), 0) AS longest
      FROM playlist_clips pc
      INNER JOIN clips c ON c.id = pc.clip_id
      WHERE pc.playlist_id = ?
    ''', [playlistId]);
    final rawNewDuration = durationRows.first['total'];
    final sumDurationMs = rawNewDuration is int
        ? rawNewDuration
        : (rawNewDuration is num ? rawNewDuration.toInt() : 0);
    final rawLongest = durationRows.first['longest'];
    final maxDurationMs = rawLongest is int
        ? rawLongest
        : (rawLongest is num ? rawLongest.toInt() : 0);
    // Shuffle-on occupies one clip per fire — conflict windows must
    // use that occupancy, not the full-playlist sum.
    final newDurationMs =
        shuffleEnabled && maxDurationMs > 0 ? maxDurationMs : sumDurationMs;
    for (final other in existing) {
      if (other.playlistId == playlistId) continue;
      if (!other.enabled) continue;
      if (_wouldConflict(
        other,
        startTime: startTime,
        endTime: endTime,
        intervalMinutes: intervalMinutes,
        daysMask: daysMask,
        playlistDurationMs: newDurationMs,
      )) {
        final suggested = _suggestNonConflictingStart(
          requested: startTime,
          endTime: endTime,
          intervalMinutes: intervalMinutes,
          daysMask: daysMask,
          playlistDurationMs: newDurationMs,
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

  /// Round 15: TRUE active-window overlap check. The previous version
  /// only looked at start-time equality, which let two playlists with
  /// the same start day but offset minutes still overlap if one's
  /// playback duration extended into the other's slot. The new check
  /// generates up to 96 successive slots (24h worth at 15-minute
  /// effective steps) of EACH schedule, computes each slot's active
  /// window `[slot, slot + playlistDurationMs]`, and reports a
  /// conflict iff ANY pair of windows on a shared weekday overlaps.
  ///
  /// User example (verbatim QA): "if a playlist is 5 minute long and
  /// starts at 9:00 with 10-minute interval, slots are 9:00, 9:15,
  /// 9:30. Another playlist of 5 minutes must not overlap those
  /// 5-minute active windows." So `(9:00, 5min)` blocks `[9:00, 9:05]`,
  /// `(9:03, 5min)` would conflict (window `[9:03, 9:08]` overlaps
  /// `[9:00, 9:05]`), `(9:06, 5min)` would NOT conflict (window
  /// `[9:06, 9:11]` falls in the silent gap before the next 9:15 slot).
  DateTime? _suggestNonConflictingStart({
    required DateTime requested,
    required DateTime? endTime,
    required int intervalMinutes,
    required int daysMask,
    required int playlistDurationMs,
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
            playlistDurationMs: playlistDurationMs,
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
    required int playlistDurationMs,
  }) {
    final sharedDays = existing.daysMask & daysMask;
    if (sharedDays == 0) return false;

    final existingOccupancy = existing.occupancyDurationMs;
    final existingStep = existing.intervalMinutes +
        (existingOccupancy > 0 ? ((existingOccupancy + 59999) ~/ 60000) : 0);
    final newStep = intervalMinutes +
        (playlistDurationMs > 0 ? ((playlistDurationMs + 59999) ~/ 60000) : 0);
    if (existingStep < 1 || newStep < 1) return false;

    final newDurationMin =
        playlistDurationMs > 0 ? ((playlistDurationMs + 59999) ~/ 60000) : 1;
    final existingDurationMin =
        existingOccupancy > 0 ? ((existingOccupancy + 59999) ~/ 60000) : 1;

    // For each shared weekday, expand both schedules into minute-of-day
    // windows. Cap the per-schedule expansion at 200 slots so a 1-minute
    // step doesn't explode runtime — that's still 200 × 24h coverage
    // for typical 7-day-mask intervals.
    const maxSlotsPerSchedule = 200;
    final existingWindows = <(int, int)>[];
    final newWindows = <(int, int)>[];

    int dayWindowEnd(PlaybackSchedule s) {
      if (s.endTime != null) {
        return s.endTime!.hour * 60 + s.endTime!.minute;
      }
      return 24 * 60;
    }

    int newDayWindowEnd() {
      if (endTime != null) {
        return endTime.hour * 60 + endTime.minute;
      }
      return 24 * 60;
    }

    for (var bit = 0; bit < 7; bit++) {
      if ((sharedDays & (1 << bit)) == 0) continue;

      existingWindows.clear();
      newWindows.clear();

      // Existing schedule slots for this weekday.
      final existingDayEnd = dayWindowEnd(existing);
      var t = existing.startTime.hour * 60 + existing.startTime.minute;
      var count = 0;
      while (t < existingDayEnd && count < maxSlotsPerSchedule) {
        existingWindows.add((t, t + existingDurationMin));
        t += existingStep;
        count++;
      }

      // New schedule slots for this weekday.
      final newDayEnd = newDayWindowEnd();
      var n = startTime.hour * 60 + startTime.minute;
      count = 0;
      while (n < newDayEnd && count < maxSlotsPerSchedule) {
        newWindows.add((n, n + newDurationMin));
        n += newStep;
        count++;
      }

      // O(N*M) overlap check. Both sides are <= 200 → up to 40k pair
      // tests. In practice both are <= 50 because typical playlist
      // gaps are minutes not seconds, so this completes in micro-
      // seconds. We short-circuit on the first overlap found.
      for (final a in existingWindows) {
        for (final b in newWindows) {
          // Half-open intervals: [a.start, a.end) ∩ [b.start, b.end)
          // overlap iff a.start < b.end AND b.start < a.end.
          if (a.$1 < b.$2 && b.$1 < a.$2) return true;
        }
      }
    }
    return false;
  }

  PlaybackSchedule _fromRow(Map<String, Object?> row) {
    final endRaw = row['end_time'] as String?;
    // `playlist_duration_ms` can come back as either int (sqflite Android)
    // or num (sqflite_common) depending on platform; coerce to int.
    final rawDuration = row['playlist_duration_ms'];
    final durationMs = rawDuration is int
        ? rawDuration
        : (rawDuration is num ? rawDuration.toInt() : 0);
    final rawMax = row['max_clip_duration_ms'];
    final maxClipMs =
        rawMax is int ? rawMax : (rawMax is num ? rawMax.toInt() : 0);
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
      maxClipDurationMs: maxClipMs,
    );
  }
}
