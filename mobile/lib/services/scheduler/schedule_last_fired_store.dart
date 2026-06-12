import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last time each schedule fired so intervals survive restarts.
class ScheduleLastFiredStore {
  ScheduleLastFiredStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'schedule_last_fired_';

  static ScheduleLastFiredStore? _cached;

  static Future<ScheduleLastFiredStore> ensureLoaded() async {
    return _cached ??= ScheduleLastFiredStore(await SharedPreferences.getInstance());
  }

  static ScheduleLastFiredStore get instance {
    final store = _cached;
    assert(store != null, 'Call ScheduleLastFiredStore.ensureLoaded() first');
    return store!;
  }

  DateTime? get(String scheduleId) {
    final raw = _prefs.getString('$_prefix$scheduleId');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> set(String scheduleId, DateTime when) async {
    await _prefs.setString('$_prefix$scheduleId', when.toIso8601String());
  }

  Future<void> clear(String scheduleId) async {
    await _prefs.remove('$_prefix$scheduleId');
  }
}
