// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/playlist_repository.dart';
import '../../domain/entities/playback_schedule.dart';
import 'schedule_fire_helper.dart';
import 'schedule_last_fired_store.dart';

/// Round 21 — bridge to the native Android alarm-clock scheduler.
///
/// The native side (Kotlin `WhisperAlarmScheduler`) owns the actual
/// `AlarmManager` table. This Dart helper turns the user's
/// `PlaybackSchedule` list into a JSON snapshot of upcoming fires and
/// ships it across the platform channel. The native side then registers
/// one `setAlarmClock` PendingIntent per fire; when an alarm fires it
/// starts a typed `mediaPlayback` foreground service that plays the
/// resolved clip.
///
/// We refresh the snapshot on:
///   • App start
///   • Active toggle on/off
///   • Schedule create / update / delete
///   • App resume (in case the user changed system time/timezone)
///   • Every successful scheduled fire (advances the "completed" cursor)
///
/// We cap the snapshot at [_kMaxFiresPerSchedule] fires per schedule and
/// [_kMaxFiresTotal] fires overall, so a hyper-active schedule doesn't
/// crowd out the others. The native scheduler ALSO enforces a 192-alarm
/// hard cap as a safety net.
class NativeAlarmsBridge {
  NativeAlarmsBridge._();
  static final NativeAlarmsBridge instance = NativeAlarmsBridge._();

  static const MethodChannel _channel = MethodChannel('com.whisperback.alarms');

  /// Up to ~24 hours of fires per schedule (1-minute schedules cap at 1440;
  /// the snapshot cap of 24 plays nicely with our typical 30/60-minute
  /// intervals while letting fine-grained schedules survive overnight).
  static const int _kMaxFiresPerSchedule = 48;
  static const int _kMaxFiresTotal = 180;

  Future<void> applySnapshot({
    required Iterable<PlaybackSchedule> schedules,
    required PlaylistRepository playlists,
    required bool active,
  }) async {
    if (!Platform.isAndroid) return;
    if (!active) {
      await cancelAll();
      return;
    }
    final enabled = schedules.where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      await cancelAll();
      return;
    }
    final fires = <Map<String, Object?>>[];
    final now = DateTime.now();
    final lastFired = ScheduleLastFiredStore.instance;
    for (final schedule in enabled) {
      String? clipPath;
      String clipTitle = 'WhisperBack';
      try {
        final list = await playlists.getClips(schedule.playlistId);
        for (final clip in list) {
          final path = clip.filePath;
          if (path.isEmpty) continue;
          if (!await File(path).exists()) continue;
          clipPath = path;
          clipTitle = clip.title.isNotEmpty ? clip.title : clipTitle;
          break;
        }
      } catch (e, st) {
        if (kDebugMode) {
          print('NativeAlarmsBridge: resolve clip for ${schedule.id} failed: $e\n$st');
        }
      }
      if (clipPath == null) continue;
      var lastCompletion = lastFired.completion(schedule.id);
      var lastSlot = lastFired.slot(schedule.id);
      var added = 0;
      var cursor = now;
      while (added < _kMaxFiresPerSchedule) {
        final next = ScheduleFireHelper.nextFireTime(
          schedule,
          cursor,
          lastFired: lastCompletion,
          lastSlot: lastSlot,
          forDisplay: true,
        );
        if (next == null) break;
        if (!next.isAfter(now)) break;
        fires.add({
          'scheduleId': schedule.id,
          'clipPath': clipPath,
          'clipTitle': clipTitle,
          'playlistName':
              schedule.playlistName.isNotEmpty ? schedule.playlistName : 'WhisperBack',
          'fireEpochMs': next.millisecondsSinceEpoch,
        });
        added++;
        lastSlot = next;
        lastCompletion = next.add(Duration(milliseconds: schedule.playlistDurationMs));
        // Move the cursor PAST this slot so the helper returns the next one.
        cursor = next.add(const Duration(seconds: 1));
        if (fires.length >= _kMaxFiresTotal) break;
      }
      if (fires.length >= _kMaxFiresTotal) break;
    }
    fires.sort((a, b) =>
        (a['fireEpochMs']! as int).compareTo(b['fireEpochMs']! as int));
    final json = jsonEncode(fires.take(_kMaxFiresTotal).toList());
    try {
      final registered = await _channel.invokeMethod<int>('setSnapshot', {
        'snapshot': json,
        'active': active,
      });
      if (kDebugMode) {
        print('NativeAlarmsBridge: native registered $registered alarms');
      }
    } on MissingPluginException {
      if (kDebugMode) {
        print('NativeAlarmsBridge: native channel missing (non-Android?)');
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.setSnapshot failed: $e\n$st');
      }
    }
  }

  Future<void> cancelAll() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // Not running on Android — silently ignore.
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.cancelAll failed: $e\n$st');
      }
    }
  }
}
