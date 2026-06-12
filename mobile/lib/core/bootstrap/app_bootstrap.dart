import '../../data/database/database_helper.dart';
import '../../data/database/seed_service.dart';
import '../../services/scheduler/schedule_last_fired_store.dart';

/// One-time startup work: SQLite warm-open + demo seed.
///
/// Intentionally local-only (no network) so startup stays instant. Fonts are
/// fetched lazily by google_fonts with a system fallback, so we never block
/// the first frame on them.
abstract final class AppBootstrap {
  static Future<void>? _ready;

  /// Safe to call multiple times; runs once per app process.
  static Future<void> ensureReady() {
    _ready ??= _run();
    return _ready!;
  }

  static Future<void> _run() async {
    await DatabaseHelper.instance.database;
    await SeedService.seedIfEmpty();
    await ScheduleLastFiredStore.ensureLoaded();
  }
}
