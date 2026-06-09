import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/schedule_repository.dart';
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

  if (active) {
    await service.showActiveOngoing(scheduleCount: armed);
  } else {
    await service.cancelActiveOngoing();
  }
  await service.syncSchedules(all, active: active);
}
