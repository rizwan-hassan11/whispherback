import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/playback/playback_state.dart';
import '../services/audio/audio_services.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/prayer/prayer_service.dart';
import 'repository_providers.dart';

final audioPlaybackServiceProvider = Provider<AudioPlaybackService>((ref) {
  final service = AudioPlaybackService();
  ref.onDispose(service.dispose);
  return service;
});

final audioRecordingServiceProvider = Provider<AudioRecordingService>((ref) {
  final service = AudioRecordingService(ref.watch(clipRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

final audioImportServiceProvider = Provider<AudioImportService>((ref) {
  return AudioImportService(ref.watch(clipRepositoryProvider));
});

final prayerServiceProvider = Provider<PrayerService>((ref) {
  return PrayerService(ref.watch(prayerRepositoryProvider));
});

final playbackCoordinatorProvider = Provider<PlaybackCoordinator>((ref) {
  final coordinator = PlaybackCoordinator(
    appStateRepository: ref.watch(appStateRepositoryProvider),
    playlistRepository: ref.watch(playlistRepositoryProvider),
    scheduleRepository: ref.watch(scheduleRepositoryProvider),
    sleepRepository: ref.watch(sleepRepositoryProvider),
    prayerService: ref.watch(prayerServiceProvider),
    playbackService: ref.watch(audioPlaybackServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  coordinator.initialize();
  return coordinator;
});

final playbackSnapshotProvider = StreamProvider<PlaybackSnapshot>((ref) {
  return ref.watch(playbackCoordinatorProvider).snapshotStream;
});

final isAppActiveProvider = FutureProvider<bool>((ref) {
  return ref.watch(appStateRepositoryProvider).isActive();
});

final playlistsProvider = FutureProvider((ref) {
  return ref.watch(playlistRepositoryProvider).getAll();
});

final clipsProvider = FutureProvider((ref) {
  return ref.watch(clipRepositoryProvider).getAll();
});

final schedulesProvider = FutureProvider((ref) {
  return ref.watch(scheduleRepositoryProvider).getAll();
});

final activeSleepProvider = FutureProvider((ref) {
  return ref.watch(sleepRepositoryProvider).getActive();
});

final prayerSettingsProvider = FutureProvider((ref) {
  return ref.watch(prayerRepositoryProvider).getSettings();
});
