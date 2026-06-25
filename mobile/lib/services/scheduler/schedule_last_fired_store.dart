import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last time each schedule fired so intervals survive restarts.
///
/// We track TWO timestamps per schedule:
///
/// * **slot** — the grid time the engine claimed (e.g. 09:00). Used purely
///   for deduplication (don't fire the same slot twice, don't let another
///   schedule steal a slot that's in flight). Always wall-clock equal to a
///   real interval boundary.
/// * **completion** — when playback actually finished. Used to compute the
///   NEXT slot via interval-from-end (`completion + intervalMinutes`).
///
/// Splitting these prevents two regressions that surfaced after the
/// "interval-from-end" feature shipped:
///   1. `_slotTakenByOtherSchedule` compared minute components against
///      `completion` (e.g. 09:04) instead of `slot` (09:00) and stopped
///      detecting overlap.
///   2. `_lastFiredForToday` rejected overnight sessions whose `lastFired`
///      crossed midnight, allowing the same slot to fire twice in one
///      session.
class ScheduleLastFiredStore {
  ScheduleLastFiredStore(this._prefs);

  final SharedPreferences _prefs;
  static const _slotPrefix = 'schedule_last_slot_';
  static const _completionPrefix = 'schedule_last_completion_';
  // Legacy single-timestamp key (pre-v9). We migrate-on-read so we don't lose
  // dedup info after upgrading.
  static const _legacyPrefix = 'schedule_last_fired_';

  static ScheduleLastFiredStore? _cached;

  static Future<ScheduleLastFiredStore> ensureLoaded() async {
    return _cached ??=
        ScheduleLastFiredStore(await SharedPreferences.getInstance());
  }

  static ScheduleLastFiredStore get instance {
    final store = _cached;
    assert(store != null, 'Call ScheduleLastFiredStore.ensureLoaded() first');
    return store!;
  }

  /// Grid slot stamp (e.g. 09:00). Used to dedupe within a single slot tick.
  DateTime? slot(String scheduleId) {
    final raw = _prefs.getString('$_slotPrefix$scheduleId') ??
        _prefs.getString('$_legacyPrefix$scheduleId');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Actual playback completion stamp. Used to compute the next slot as
  /// `completion + intervalMinutes`.
  DateTime? completion(String scheduleId) {
    final raw = _prefs.getString('$_completionPrefix$scheduleId') ??
        _prefs.getString('$_legacyPrefix$scheduleId');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Backwards-compat for older callers. Returns the completion stamp when
  /// available, falling back to the slot stamp. Most callsites should
  /// switch to [slot] or [completion] explicitly.
  DateTime? get(String scheduleId) =>
      completion(scheduleId) ?? slot(scheduleId);

  Future<void> setSlot(String scheduleId, DateTime when) async {
    await _prefs.setString(
      '$_slotPrefix$scheduleId',
      when.toIso8601String(),
    );
  }

  Future<void> setCompletion(String scheduleId, DateTime when) async {
    await _prefs.setString(
      '$_completionPrefix$scheduleId',
      when.toIso8601String(),
    );
  }

  /// Legacy combined setter for one-shot stamps where slot == completion.
  /// Maintained for tests that pre-date the split.
  Future<void> set(String scheduleId, DateTime when) async {
    await setSlot(scheduleId, when);
    await setCompletion(scheduleId, when);
  }

  Future<void> clear(String scheduleId) async {
    await _prefs.remove('$_slotPrefix$scheduleId');
    await _prefs.remove('$_completionPrefix$scheduleId');
    await _prefs.remove('$_legacyPrefix$scheduleId');
  }
}
