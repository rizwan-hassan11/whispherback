import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../audio/whisper_audio_handler.dart';
import '../scheduler/schedule_fire_helper.dart';
import '../scheduler/schedule_last_fired_store.dart';
import 'notification_service.dart';

/// Reconciles system notifications with the current app state:
/// shows/hides the persistent "active" notification and re-arms scheduled
/// alarms. Call after toggling Active, after any schedule change, and after
/// each scheduled fire so "next up" stays accurate.
Future<void> syncWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
}) async {
  final service = NotificationService.instance;
  await service.init();

  final active = await appState.isActive();
  final all = await schedules.getAll();
  final enabled = all.where((s) => s.enabled).toList();
  final armed = enabled.length;
  final now = DateTime.now();
  final lastFired = ScheduleLastFiredStore.instance;

  final upcoming = ScheduleFireHelper.upcomingEvents(
    enabled,
    now,
    lastFiredFor: lastFired.get,
    limit: 4,
  );

  String? nextUpcoming;
  if (upcoming.isNotEmpty) {
    nextUpcoming =
        'Next: “${upcoming.first.playlistName}” at ${_formatTime(upcoming.first.when)}';
  }

  if (active) {
    final subtitle = nextUpcoming ??
        (armed > 0
            ? '$armed schedule(s) armed · whispers will play automatically'
            : 'Listening for scheduled whispers');
    await whisperAudioHandler.updateActiveSessionInfo(
      subtitle: subtitle,
      scheduleCount: armed,
    );
    // Media controls + lock screen come from audio_service — cancel the old
    // low-priority status notification so it doesn't hide the media card.
    await service.cancelActiveOngoing();
  } else {
    await service.cancelActiveOngoing();
  }
  await service.syncSchedules(all, active: active);
}

String _formatTime(DateTime when) {
  final h = when.hour;
  final m = when.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:$m $period';
}

/// Refresh notifications after playback events (scheduled clip finished, etc.).
Future<void> refreshWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
}) =>
    syncWhisperNotifications(appState: appState, schedules: schedules);
