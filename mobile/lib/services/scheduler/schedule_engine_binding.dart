typedef ScheduleFireCallback = Future<void> Function();

/// Lets notification callbacks and lifecycle hooks reach the live engine without
/// Riverpod (required for background notification entry points).
class ScheduleEngineBinding {
  ScheduleEngineBinding._();

  static final ScheduleEngineBinding instance = ScheduleEngineBinding._();

  ScheduleFireCallback? _fire;

  void attach(ScheduleFireCallback fire) => _fire = fire;

  void detach() => _fire = null;

  Future<void> fireNow() async {
    await _fire?.call();
  }
}
