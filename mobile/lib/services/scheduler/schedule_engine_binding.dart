typedef ScheduleFireCallback = Future<void> Function({bool force});

/// Lets notification callbacks and lifecycle hooks reach the live engine without
/// Riverpod (required for background notification entry points).
class ScheduleEngineBinding {
  ScheduleEngineBinding._();

  static final ScheduleEngineBinding instance = ScheduleEngineBinding._();

  ScheduleFireCallback? _fire;

  void attach(ScheduleFireCallback fire) => _fire = fire;

  void detach() => _fire = null;

  /// [force] bypasses the engine's lateness cap. Use when the user
  /// manually wakes the engine via an alarm tap so a slot that the OS
  /// missed by more than [ScheduleFireHelper.maxLateness] still plays.
  Future<void> fireNow({bool force = false}) async {
    await _fire?.call(force: force);
  }
}
