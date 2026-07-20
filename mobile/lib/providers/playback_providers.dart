import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/playback/playback_state.dart';
import '../data/repositories/clip_repository.dart';
import '../services/audio/audio_services.dart';
import '../services/audio/whisper_audio_handler.dart';
import '../services/notifications/notification_sync.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/prayer/prayer_service.dart';
import '../services/scheduler/native_alarms_bridge.dart';
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
  coordinator.refreshScheduleNotifications =
      ({bool forceAlarmRebuild = false}) async {
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      prayer: ref.read(prayerRepositoryProvider),
      forceAlarmRebuild: forceAlarmRebuild,
    );
  };
  ref.onDispose(coordinator.dispose);
  coordinator.initialize();
  return coordinator;
});

final playbackSnapshotProvider = StreamProvider<PlaybackSnapshot>((ref) {
  return ref.watch(playbackCoordinatorProvider).snapshotStream;
});

/// Round 31 / 34 — drives mini-player visibility from native prefs/stream.
/// Polls every 1.5s so Activity destruction (which used to null the
/// method-channel listener) cannot leave the Spotify bar hidden while
/// MediaPlayer is still audible.
final nativePlaybackProvider =
    StreamProvider<NativePlaybackSnapshot>((ref) async* {
  yield await NativeAlarmsBridge.instance.fetchPlaybackState();
  final controller = StreamController<NativePlaybackSnapshot>();
  StreamSubscription<NativePlaybackSnapshot>? sub;
  Timer? poll;
  void emit(NativePlaybackSnapshot snap) {
    if (!controller.isClosed) controller.add(snap);
  }

  sub = NativeAlarmsBridge.instance.stateStream.listen(emit);
  poll = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
    try {
      final snap = await NativeAlarmsBridge.instance.fetchPlaybackState();
      emit(snap);
    } catch (_) {}
  });
  ref.onDispose(() {
    sub?.cancel();
    poll?.cancel();
    controller.close();
  });
  yield* controller.stream;
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
  // Round 24 — auto-invalidate whenever the native duration probe finishes
  // backfilling a clip so the tile re-renders with the real length instead
  // of the placeholder 0:00. Without this, the user sees "0:00" until they
  // manually pull to refresh — the user's QA "clip card only shows 0:00
  // instead of the actual length" was this exact missing wiring.
  final sub = ClipRepository.onDurationBackfilled.listen((_) {
    // Debounce not required: backfills fire once per new clip and
    // there's at most one active recording/import at a time. If we
    // ever bulk-import, riverpod naturally coalesces repeated
    // invalidations within a frame.
    ref.invalidateSelf();
    // Round 34: duration was 0 when alarms were first armed → later
    // fires were early by ~clip length. Force alarm realign once the
    // native probe writes the real length.
    unawaited(() async {
      try {
        await syncWhisperNotifications(
          appState: ref.read(appStateRepositoryProvider),
          schedules: ref.read(scheduleRepositoryProvider),
          prayer: ref.read(prayerRepositoryProvider),
          forceAlarmRebuild: true,
        );
      } catch (_) {}
    }());
  });
  ref.onDispose(sub.cancel);
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
