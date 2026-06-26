import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/playback/playback_state.dart';
import '../services/audio/audio_services.dart';
import '../services/audio/whisper_audio_handler.dart';
import '../services/notifications/notification_sync.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/prayer/prayer_service.dart';
import 'repository_providers.dart';

final audioPlaybackServiceProvider = Provider<AudioPlaybackService>((ref) {
  // Backed by the app-wide audio_service handler (foreground service).
  return AudioPlaybackService(whisperAudioHandler);
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
    sleepRepository: ref.watch(sleepRepositoryProvider),
    prayerService: ref.watch(prayerServiceProvider),
    playbackService: ref.watch(audioPlaybackServiceProvider),
    scheduleRepository: ref.watch(scheduleRepositoryProvider),
  );
  coordinator.refreshScheduleNotifications = () async {
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      prayer: ref.read(prayerRepositoryProvider),
    );
  };
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
  ref.keepAlive();
  return ref.watch(playlistRepositoryProvider).getAll();
});

final clipsProvider = FutureProvider((ref) {
  ref.keepAlive();
  return ref.watch(clipRepositoryProvider).getAll();
});

final schedulesProvider = FutureProvider((ref) {
  ref.keepAlive();
  return ref.watch(scheduleRepositoryProvider).getAll();
});

final activeSleepProvider = FutureProvider((ref) {
  ref.keepAlive();
  return ref.watch(sleepRepositoryProvider).getActive();
});

final prayerSettingsProvider = FutureProvider((ref) {
  ref.keepAlive();
  return ref.watch(prayerRepositoryProvider).getSettings();
});
