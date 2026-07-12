import 'package:flutter/foundation.dart';

import '../../core/config/feature_flags.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/prayer_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../audio/whisper_audio_handler.dart';
import '../prayer/prayer_notification_scheduler.dart';
import '../scheduler/native_alarms_bridge.dart';
import '../scheduler/schedule_fire_helper.dart';
import '../scheduler/schedule_last_fired_store.dart';
import '../../l10n/runtime_copy.dart';
import 'notification_service.dart';

/// Round 21 — global PlaylistRepository handle used by `syncWhisperNotifications`
/// when the caller didn't pass one explicitly. The app's bootstrap path
/// registers it once before the first sync; resetting to null in tests is
/// fine (the bridge silently no-ops when playlists is null).
PlaylistRepository? _playlistsForBridge;

void registerPlaylistRepositoryForBridge(PlaylistRepository? repo) {
  _playlistsForBridge = repo;
}

/// • **Idle + Active** → flutter status notification (schedule summary)
/// • **Clip playing** → [audio_service] Spotify-style media notification only
///
/// Best-effort: never throws. Notification permissions, exact-alarm permission
/// (Android 14+), or geolocation failures are all swallowed and logged so a
/// schedule Save flow never surfaces a false error to the user.
Future<void> syncWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
  PlaylistRepository? playlists,
  PrayerRepository? prayer,
  bool forceAlarmRebuild = false,
}) async {
  try {
    final service = NotificationService.instance;
    await service.init();

    final active = await appState.isActive();
    final all = await schedules.getAll();
    final enabled = all.where((s) => s.enabled).toList();
    final armed = enabled.length;
    final now = DateTime.now();
    final lastFired = ScheduleLastFiredStore.instance;
    final handler = whisperAudioHandler;
    final playingClip = handler.isPlayingClip;

    // Build a rolling list of upcoming fires across all schedules. For
    // each schedule we walk forward `kMaxUpcomingPerSchedule` steps so a
    // single under-used schedule doesn't crowd out the next-most-likely
    // events. We collect across schedules, sort, then take the top
    // `kMaxUpcomingNotification` (5 — user explicitly requested at
    // least 5 upcoming entries in the notification summary).
    //
    // Critically, we pass `forDisplay: true` so the helper never
    // surfaces a slot that's already in the past — the QA report
    // "notification shows next will be in 1:18 when it's 1:20" was
    // because the helper's lateness grace window let a 2-minute-old
    // slot through.
    const kMaxUpcomingPerSchedule = 4;
    const kMaxUpcomingNotification = 5;
    final upcoming = <({DateTime when, String playlistName})>[];
    for (final s in enabled) {
      final lastSlot = lastFired.slot(s.id);
      final lastCompletion = lastFired.completion(s.id);
      var cursorSlot = lastSlot;
      var cursorFired = lastCompletion;
      for (var step = 0; step < kMaxUpcomingPerSchedule; step++) {
        final nextWhen = ScheduleFireHelper.nextFireTime(
          s,
          now,
          lastFired: cursorFired,
          lastSlot: cursorSlot,
          forDisplay: true,
        );
        if (nextWhen == null) break;
        if (!nextWhen.isAfter(now)) break;
        upcoming.add((
          when: nextWhen,
          playlistName:
              s.playlistName.isEmpty ? 'WhisperBack' : s.playlistName,
        ));
        // Advance the cursor for the NEXT iteration. We pretend this
        // event has just completed (slot = nextWhen, completion =
        // nextWhen + playlistDuration) so the next iteration projects
        // the slot AFTER it.
        cursorSlot = nextWhen;
        cursorFired =
            nextWhen.add(Duration(milliseconds: s.playlistDurationMs));
      }
    }
    upcoming.sort((a, b) => a.when.compareTo(b.when));
    final topUpcoming = upcoming.take(kMaxUpcomingNotification).toList();

    String? nextUpcoming;
    String? upcomingSummary;
    final copy = RuntimeCopy.l10n;
    if (topUpcoming.isNotEmpty) {
      nextUpcoming = copy.notificationNextUpcoming(
        topUpcoming.first.playlistName,
        _formatTime(topUpcoming.first.when),
      );
      if (topUpcoming.length > 1) {
        upcomingSummary = topUpcoming
            .map((e) => '• ${_formatTime(e.when)} — ${e.playlistName}')
            .join('\n');
      }
    }

    if (active) {
      // Refresh the silent keep-alive (best-effort — failures must not
      // block the visible notification below).
      try {
        await handler.updateActiveSessionInfo();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('updateActiveSessionInfo failed (handled): $e');
        }
      }
      // Round 21: ALWAYS publish the WhisperBack ongoing schedule card
      // while Active is ON — INCLUDING while a clip is playing in the
      // mini-player. Previously we cancelled this card the moment a
      // clip started, which is why the user reported "the notification
      // bar with the schedules becomes hidden sometimes when the app is
      // opened or clips is playing or when mini-player is working".
      // The audio_service media-controls notification and our schedule
      // card are independent (different IDs, different channels) so
      // both can — and now do — coexist exactly like a music player
      // alongside an alarm clock.
      await service.showActiveOngoing(
        scheduleCount: armed,
        nextUpcoming: nextUpcoming,
        upcomingSummary: upcomingSummary,
      );
      if (playingClip && kDebugMode) {
        debugPrint('syncWhisperNotifications: keeping active card up '
            'alongside the now-playing media controls');
      }
    } else {
      await service.cancelActiveOngoing();
    }

    await service.syncSchedules(all, active: active);

    // Round 21: drive the native alarm-clock scheduler. This is the
    // path that actually plays scheduled audio when the app is closed
    // (the previous Round-20 Dart background isolate couldn't acquire
    // audio focus from a non-FG context on Android 14+, hence the
    // user's "notification shows the slot but nothing plays"). When
    // Active is OFF — or no playlists are provided — we cancel any
    // outstanding alarms so the device can stay in Doze undisturbed.
    final resolvedPlaylists = playlists ?? _playlistsForBridge;
    if (resolvedPlaylists != null) {
      try {
        await NativeAlarmsBridge.instance.applySnapshot(
          schedules: all,
          playlists: resolvedPlaylists,
          active: active,
          // Round 24 — schedule-editor CRUD paths pass forceAlarmRebuild
          // = true so the structural fingerprint is bypassed and the
          // alarm table is guaranteed fresh even in the unlikely case
          // that the fingerprint collides (e.g. a rename that keeps
          // the same days / interval / duration produces the same
          // key). The default false path lets the fingerprint short-
          // circuit repeated calls from the 5-second notification tick.
          forceRebuild: forceAlarmRebuild,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('NativeAlarmsBridge.applySnapshot failed: $e\n$st');
        }
      }
    }

    if (prayer != null && kAdhanFeatureEnabled) {
      final prayerScheduler = PrayerNotificationScheduler(
        plugin: service.plugin,
        prayerRepository: prayer,
      );
      // Adhan reminders are independent of the Active toggle — they fire as
      // long as the user has the "Play adhan voice" setting enabled.
      await prayerScheduler.sync();
    } else if (prayer != null && !kAdhanFeatureEnabled) {
      // Shelved for this release — cancel any prayer notifications that
      // may have been scheduled by an earlier APK so they never fire.
      final prayerScheduler = PrayerNotificationScheduler(
        plugin: service.plugin,
        prayerRepository: prayer,
      );
      await prayerScheduler.cancelAllScheduled();
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('syncWhisperNotifications failed: $e\n$st');
    }
  }
}

String _formatTime(DateTime when) {
  final h = when.hour;
  final m = when.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:$m $period';
}

Future<void> refreshWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
  PlaylistRepository? playlists,
}) =>
    syncWhisperNotifications(
      appState: appState,
      schedules: schedules,
      playlists: playlists,
    );
