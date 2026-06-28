import 'package:flutter/foundation.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/prayer_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../audio/whisper_audio_handler.dart';
import '../prayer/prayer_notification_scheduler.dart';
import '../scheduler/schedule_fire_helper.dart';
import '../scheduler/schedule_last_fired_store.dart';
import '../../l10n/runtime_copy.dart';
import 'notification_service.dart';

/// • **Idle + Active** → flutter status notification (schedule summary)
/// • **Clip playing** → [audio_service] Spotify-style media notification only
///
/// Best-effort: never throws. Notification permissions, exact-alarm permission
/// (Android 14+), or geolocation failures are all swallowed and logged so a
/// schedule Save flow never surfaces a false error to the user.
Future<void> syncWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
  PrayerRepository? prayer,
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

    if (playingClip) {
      // Clip playback uses the media notification — hide the status card.
      await service.cancelActiveOngoing();
    } else if (active) {
      // Refresh the silent keep-alive (best-effort — failures must not
      // block the visible notification below).
      try {
        await handler.updateActiveSessionInfo();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('updateActiveSessionInfo failed (handled): $e');
        }
      }
      // ALWAYS publish the WhisperBack ongoing card while Active is ON.
      // Previously gated on `shouldUseFlutterActiveNotification`, which
      // returned false whenever the audio_service silence keep-alive
      // appeared to be running. On Samsung One UI 6 / Vivo Funtouch 14 /
      // Infinix XOS, the silent keep-alive card is suppressed by the OS
      // even when bound — so users saw NO notification at all, despite
      // the toggle being on. We now post our own card unconditionally;
      // if audio_service ALSO posts one, that's two cards (acceptable
      // and clearly labelled), but the user is never in the dark.
      await service.showActiveOngoing(
        scheduleCount: armed,
        nextUpcoming: nextUpcoming,
        upcomingSummary: upcomingSummary,
      );
    } else {
      await service.cancelActiveOngoing();
    }

    await service.syncSchedules(all, active: active);

    if (prayer != null) {
      final prayerScheduler = PrayerNotificationScheduler(
        plugin: service.plugin,
        prayerRepository: prayer,
      );
      // Adhan reminders are independent of the Active toggle — they fire as
      // long as the user has the "Play adhan voice" setting enabled.
      await prayerScheduler.sync();
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
}) =>
    syncWhisperNotifications(appState: appState, schedules: schedules);
