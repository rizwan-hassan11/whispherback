import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database_helper.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/clip_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/prayer_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/sleep_repository.dart';

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance;
});

final clipRepositoryProvider = Provider<ClipRepository>((ref) {
  return ClipRepository(ref.watch(databaseHelperProvider));
});

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(databaseHelperProvider));
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(ref.watch(databaseHelperProvider));
});

final sleepRepositoryProvider = Provider<SleepRepository>((ref) {
  return SleepRepository(ref.watch(databaseHelperProvider));
});

final prayerRepositoryProvider = Provider<PrayerRepository>((ref) {
  return PrayerRepository(ref.watch(databaseHelperProvider));
});

final appStateRepositoryProvider = Provider<AppStateRepository>((ref) {
  return AppStateRepository(ref.watch(databaseHelperProvider));
});
