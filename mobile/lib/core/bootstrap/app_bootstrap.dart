import 'package:google_fonts/google_fonts.dart';

import '../../data/database/database_helper.dart';
import '../../data/database/seed_service.dart';

/// One-time startup work: SQLite warm-open, demo seed, font cache.
abstract final class AppBootstrap {
  static Future<void>? _ready;

  /// Safe to call multiple times; runs once per app process.
  static Future<void> ensureReady() {
    _ready ??= _run();
    return _ready!;
  }

  static Future<void> _run() async {
    await Future.wait([
      DatabaseHelper.instance.database,
      SeedService.seedIfEmpty(),
      _preloadFonts(),
    ]);
  }

  static Future<void> _preloadFonts() async {
    try {
      await GoogleFonts.pendingFonts([
        GoogleFonts.fraunces(),
        GoogleFonts.dmSans(),
      ]);
    } catch (_) {
      // Offline: theme falls back to system sans-serif.
    }
  }
}
