// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// True background scheduled-audio path that survives the main Dart isolate
/// being killed by aggressive OEM battery managers (Vivo Funtouch, Xiaomi
/// MIUI, Samsung One UI when battery exemption is denied).
///
/// Architecture:
///   • The notification-sync layer registers ONE periodic
///     [AndroidAlarmManager] alarm every minute. The alarm wakes a fresh
///     background isolate (separate from the main app isolate) and runs
///     [backgroundScheduledPlaybackTick].
///   • That tick opens the SQLite DB directly, walks the enabled schedules,
///     and for any schedule whose slot is due RIGHT NOW (no grace window —
///     we only fire within ±30 s of the slot) it picks the first playable
///     clip and plays it with a minimal `just_audio` instance.
///   • Audio output happens through a tiny `AudioPlayer` directly — no
///     audio_service, no Riverpod, no UI dependencies. This keeps the
///     isolate cold-start under 1 s even on slow Samsung firmware.
///   • The native [WhisperKeepAliveService] still owns the user-visible
///     foreground notification, so the user sees ONE persistent card
///     regardless of which isolate is currently playing.
///
/// Limitations:
///   • Background playback uses a fire-and-forget player; the next minute's
///     alarm will pick up the next slot. We do NOT update lock-screen
///     controls (audio_service is not safe to init from a background
///     isolate). If the user wants pause/resume controls, they must
///     re-open the app.
///   • Schedules with playlists > 1 clip play the FIRST clip only in the
///     background path. The user's main-isolate engine handles full
///     playlists when the app is awake.
///   • We assume `Active` is ON when we fire. The main engine's gating
///     logic is mirrored here via `app_state.is_active`.

const int periodicAlarmId = 0x7717AC;

/// Per-clip alarm callback IDs occupy this range so they don't collide with
/// the periodic id above. We hash the slot into `[base, base + 1000)`.
const int oneShotAlarmIdBase = 0x7717B0;

/// Entry point invoked by `android_alarm_manager_plus` when the periodic
/// scheduled-audio alarm fires. `@pragma('vm:entry-point')` is REQUIRED so
/// the tree shaker does not strip the symbol from release builds.
@pragma('vm:entry-point')
Future<void> backgroundScheduledPlaybackTick() async {
  // Background isolates do NOT inherit `WidgetsFlutterBinding`. Without
  // this, plugin channels (sqflite, just_audio) silently fail.
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (_) {
    // ensureInitialized is idempotent — older Flutter versions may throw if
    // the binding is already up; we don't care which one wins.
  }

  // Each iteration MUST be wrapped so a single bad clip / corrupt schedule
  // never crashes the isolate. The OS would interpret an uncaught throw as
  // "alarm callback failed" and retry the alarm with exponential backoff,
  // which delays the next legitimate fire.
  try {
    await _runBackgroundTick();
  } catch (e, st) {
    if (kDebugMode) {
      print('background alarm tick failed (swallowed): $e\n$st');
    }
  }
}

Future<void> _runBackgroundTick() async {
  final dbPath = await getDatabasesPath();
  final path = p.join(dbPath, 'whisperback.db');
  if (!File(path).existsSync()) return;

  Database? db;
  try {
    // Read-only access — we never mutate schedule state from the background
    // isolate. Stamping `lastFired` is the main engine's job; if we did it
    // here we'd race against the main engine on app resume.
    db = await openReadOnlyDatabase(path);
  } catch (e, st) {
    if (kDebugMode) {
      print('background tick: open DB failed: $e\n$st');
    }
    return;
  }

  try {
    final active = await _isActive(db);
    if (!active) return;

    final schedules = await _enabledSchedules(db);
    if (schedules.isEmpty) return;

    final now = DateTime.now();
    for (final schedule in schedules) {
      final slot = _slotDueNow(schedule, now);
      if (slot == null) continue;
      final clipPath = await _firstPlayableClipPath(db, schedule.playlistId);
      if (clipPath == null) continue;
      if (!File(clipPath).existsSync()) continue;
      await _playClip(clipPath);
      // Only fire ONE schedule per minute tick — overlapping background
      // audio is unintelligible.
      return;
    }
  } finally {
    try {
      await db.close();
    } catch (_) {}
  }
}

Future<bool> _isActive(Database db) async {
  try {
    final rows = await db.query('app_state', limit: 1);
    if (rows.isEmpty) return false;
    return (rows.first['is_active'] as int? ?? 0) == 1;
  } catch (_) {
    return false;
  }
}

Future<List<_BgSchedule>> _enabledSchedules(Database db) async {
  try {
    final rows = await db.query(
      'schedules',
      where: 'enabled = ?',
      whereArgs: [1],
    );
    return rows
        .map(_BgSchedule.fromRow)
        .where((s) => s != null)
        .cast<_BgSchedule>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<String?> _firstPlayableClipPath(Database db, String playlistId) async {
  try {
    final rows = await db.rawQuery('''
      SELECT clips.file_path AS file_path
      FROM playlist_clips
      JOIN clips ON clips.id = playlist_clips.clip_id
      WHERE playlist_clips.playlist_id = ?
      ORDER BY playlist_clips.sort_order ASC
      LIMIT 8
    ''', [playlistId]);
    for (final row in rows) {
      final path = row['file_path'] as String?;
      if (path == null || path.isEmpty) continue;
      if (File(path).existsSync()) return path;
    }
  } catch (_) {}
  return null;
}

/// Returns the slot timestamp the schedule should fire RIGHT NOW, or null.
/// Background-isolate grace window is tight (±30 seconds) — we don't want
/// to fire stale slots from a long device-asleep gap (the main engine
/// handles recovery on resume via its `force: true` cold-start path).
DateTime? _slotDueNow(_BgSchedule schedule, DateTime now) {
  if (!schedule.runsOnWeekday(now.weekday)) return null;
  final start = DateTime(now.year, now.month, now.day,
      schedule.startHour, schedule.startMinute);
  if (now.isBefore(start)) return null;
  if (schedule.endHour != null && schedule.endMinute != null) {
    final end = DateTime(
        now.year, now.month, now.day, schedule.endHour!, schedule.endMinute!);
    if (now.isAfter(end)) return null;
  }
  final step = schedule.effectiveStepMinutes;
  if (step <= 0) return null;
  final minutesSinceStart = now.difference(start).inMinutes;
  final slotIndex = minutesSinceStart ~/ step;
  final slot = start.add(Duration(minutes: slotIndex * step));
  final delta = now.difference(slot);
  // ±30 s tight window so we never surprise the user with an old missed
  // slot — that's exactly the bug the boot-window guard fixes for the
  // main engine.
  if (delta.inSeconds.abs() > 30) return null;
  return slot;
}

Future<void> _playClip(String filePath) async {
  AudioPlayer? player;
  try {
    player = AudioPlayer();
    await player.setVolume(1);
    await player
        .setAudioSource(AudioSource.file(filePath), preload: true)
        .timeout(const Duration(seconds: 8));
    await player.play();
    // Wait for the clip to finish (or timeout at 5 minutes max — most
    // whispers are <30 s; this cap is just a safety net).
    final completer = Completer<void>();
    late StreamSubscription<PlayerState> sub;
    sub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!completer.isCompleted) completer.complete();
      }
    });
    try {
      await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      // Hard cap reached — stop the player and proceed.
    } finally {
      await sub.cancel();
    }
  } catch (e, st) {
    if (kDebugMode) {
      print('background _playClip failed: $e\n$st');
    }
  } finally {
    try {
      await player?.stop();
    } catch (_) {}
    try {
      await player?.dispose();
    } catch (_) {}
  }
}

class _BgSchedule {
  _BgSchedule({
    required this.id,
    required this.playlistId,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.intervalMinutes,
    required this.playlistDurationMs,
    required this.daysMask,
  });

  final String id;
  final String playlistId;
  final int startHour;
  final int startMinute;
  final int? endHour;
  final int? endMinute;
  final int intervalMinutes;
  final int playlistDurationMs;
  final int daysMask;

  static _BgSchedule? fromRow(Map<String, Object?> row) {
    try {
      final id = row['id'] as String?;
      final playlistId = row['playlist_id'] as String?;
      final startTime = row['start_time'] as String?;
      final endTime = row['end_time'] as String?;
      final interval = row['interval_minutes'] as int?;
      final daysMask = (row['days_mask'] as int?) ?? 127;
      if (id == null || playlistId == null || startTime == null || interval == null) {
        return null;
      }
      final parts = startTime.split(':');
      if (parts.length < 2) return null;
      final sH = int.tryParse(parts[0]) ?? 0;
      final sM = int.tryParse(parts[1]) ?? 0;
      int? eH;
      int? eM;
      if (endTime != null && endTime.isNotEmpty) {
        final ep = endTime.split(':');
        if (ep.length >= 2) {
          eH = int.tryParse(ep[0]);
          eM = int.tryParse(ep[1]);
        }
      }
      return _BgSchedule(
        id: id,
        playlistId: playlistId,
        startHour: sH,
        startMinute: sM,
        endHour: eH,
        endMinute: eM,
        intervalMinutes: interval,
        // We don't store per-schedule duration in the schema yet; let the
        // step equal the interval for now. (When the main engine writes
        // duration metadata into the table we can pick it up here.)
        playlistDurationMs: 0,
        daysMask: daysMask,
      );
    } catch (_) {
      return null;
    }
  }

  bool runsOnWeekday(int weekday) {
    // bit 0 = Monday … bit 6 = Sunday (matches schedule_repository's mask).
    final bit = 1 << ((weekday - 1).clamp(0, 6));
    return (daysMask & bit) != 0;
  }

  int get effectiveStepMinutes {
    if (intervalMinutes < 1) return 1;
    final durationMinutes = playlistDurationMs > 0
        ? ((playlistDurationMs + 59999) ~/ 60000)
        : 0;
    return intervalMinutes + durationMinutes;
  }
}

/// Schedules a 1-minute periodic alarm that wakes the background isolate
/// and runs [backgroundScheduledPlaybackTick]. Safe to call repeatedly —
/// `AndroidAlarmManager.periodic` overwrites the previous registration
/// for the same id.
Future<void> ensureBackgroundAlarmRegistered() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 1),
      periodicAlarmId,
      backgroundScheduledPlaybackTick,
      wakeup: true,
      rescheduleOnReboot: true,
      exact: true,
      allowWhileIdle: true,
    );
  } on PlatformException catch (e, st) {
    if (kDebugMode) {
      print('ensureBackgroundAlarmRegistered failed: $e\n$st');
    }
  } catch (e, st) {
    if (kDebugMode) {
      print('ensureBackgroundAlarmRegistered failed: $e\n$st');
    }
  }
}

/// Cancels the background periodic alarm. Used when the user toggles
/// Active OFF (no need to keep firing alarms with nothing to play).
Future<void> cancelBackgroundAlarm() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.cancel(periodicAlarmId);
  } catch (_) {}
}

/// Initializes `android_alarm_manager_plus`. MUST be called from `main()`
/// before any `AndroidAlarmManager.periodic`/`oneShotAt` call. Idempotent.
Future<void> initializeBackgroundAlarms() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.initialize();
  } catch (e, st) {
    if (kDebugMode) {
      print('AndroidAlarmManager.initialize failed: $e\n$st');
    }
  }
}

/// Sends a signal back to the main isolate (when alive) that a background
/// fire happened, so the main engine can stamp `setSlot`/`setCompletion`
/// and avoid double-firing. Best-effort: silent no-op when no main
/// isolate is listening.
@pragma('vm:entry-point')
void notifyMainIsolateOfFire(String scheduleId, DateTime slot) {
  try {
    final port = IsolateNameServer.lookupPortByName(_bgFirePortName);
    port?.send({'scheduleId': scheduleId, 'slotMs': slot.millisecondsSinceEpoch});
  } catch (_) {}
}

const String _bgFirePortName = 'whisperback_bg_fire_port';

/// Registers a port on the main isolate so the background tick can notify
/// it of a fire (for stamping). Call from app bootstrap.
ReceivePort? subscribeToBackgroundFires(
    void Function(String scheduleId, DateTime slot) onFire) {
  if (!Platform.isAndroid) return null;
  final port = ReceivePort();
  try {
    IsolateNameServer.removePortNameMapping(_bgFirePortName);
    IsolateNameServer.registerPortWithName(port.sendPort, _bgFirePortName);
  } catch (_) {}
  port.listen((message) {
    if (message is Map) {
      final id = message['scheduleId'] as String?;
      final slotMs = message['slotMs'] as int?;
      if (id != null && slotMs != null) {
        onFire(id, DateTime.fromMillisecondsSinceEpoch(slotMs));
      }
    }
  });
  return port;
}
