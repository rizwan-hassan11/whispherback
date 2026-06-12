import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../audio/whisper_audio_handler.dart';
import '../scheduler/schedule_fire_helper.dart';
import 'notification_service.dart';

/// Reconciles system notifications with the current app state:
/// shows/hides the persistent "active" notification and re-arms scheduled
/// alarms. Call after toggling Active and after any schedule change.
Future<void> syncWhisperNotifications({
  required AppStateRepository appState,
  required ScheduleRepository schedules,
}) async {
  final service = NotificationService.instance;
  await service.init();

  final active = await appState.isActive();
  final all = await schedules.getAll();
  final armed = all.where((s) => s.enabled).length;

  String? nextUpcoming;
  final next = ScheduleFireHelper.nextUpcoming(
    all.where((s) => s.enabled).toList(),
    DateTime.now(),
  );
  if (next != null) {
    final name = next.schedule.playlistName.isEmpty
        ? 'WhisperBack'
        : next.schedule.playlistName;
    final time = _formatTime(next.when);
    nextUpcoming = 'Next: “$name” at $time';
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
