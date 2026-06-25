import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/playback_schedule.dart';
import '../database/database_helper.dart';

class ScheduleConflictException implements Exception {
  ScheduleConflictException(this.existingPlaylistName);
  final String existingPlaylistName;
}

class ScheduleRepository {
  ScheduleRepository(this._db);

  final DatabaseHelper _db;
  final _uuid = const Uuid();

  Future<List<PlaybackSchedule>> getAll() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT s.*, p.name AS playlist_name
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
      SELECT s.*, p.name AS playlist_name
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
        throw ScheduleConflictException(other.playlistName);
      }
    }

    final scheduleId = id ?? _uuid.v4();
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
        'enabled': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final rows = await db.rawQuery(
      '''
      SELECT s.*, p.name AS playlist_name
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

  bool _wouldConflict(
    PlaybackSchedule existing, {
    required DateTime startTime,
    required DateTime? endTime,
    required int intervalMinutes,
    required int daysMask,
  }) {
    if ((existing.daysMask & daysMask) == 0) return false;

    final existingSlots = _slotSeconds(
      existing.startTime,
      existing.endTime,
      existing.intervalMinutes,
    );
    final newSlots = _slotSeconds(startTime, endTime, intervalMinutes);

    for (final a in existingSlots) {
      for (final b in newSlots) {
        if ((a - b).abs() < 30) return true;
      }
    }
    return false;
  }

  /// Seconds since midnight for each grid slot (30s conflict tolerance).
  List<int> _slotSeconds(
    DateTime start,
    DateTime? end,
    int intervalMinutes,
  ) {
    final startSeconds = start.hour * 3600 + start.minute * 60 + start.second;
    final endMinutes = end != null ? end.hour * 60 + end.minute : null;
    final startMinutes = start.hour * 60 + start.minute;
    final overnight = endMinutes != null && endMinutes <= startMinutes;
    final windowEndSeconds = endMinutes == null
        ? startSeconds + (24 * 3600)
        : (overnight ? endMinutes * 60 + 24 * 3600 : endMinutes * 60);

    final slots = <int>[];
    var cursor = startSeconds;
    while (cursor <= windowEndSeconds) {
      slots.add(cursor % (24 * 3600));
      cursor += intervalMinutes * 60;
      if (slots.length > 500) break;
    }
    return slots;
  }

  PlaybackSchedule _fromRow(Map<String, Object?> row) {
    final endRaw = row['end_time'] as String?;
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
    );
  }
}
