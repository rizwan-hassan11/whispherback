import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/entities/audio_clip.dart';
import '../../domain/playback/playback_state.dart';
import '../audio/audio_services.dart';
import '../prayer/prayer_service.dart';
import '../shuffle/shuffle_engine.dart';

class PlaybackCoordinator {
  PlaybackCoordinator({
    required AppStateRepository appStateRepository,
    required PlaylistRepository playlistRepository,
    required ScheduleRepository scheduleRepository,
    required SleepRepository sleepRepository,
    required PrayerService prayerService,
    required AudioPlaybackService playbackService,
  })  : _appState = appStateRepository,
        _playlists = playlistRepository,
        _schedules = scheduleRepository,
        _sleep = sleepRepository,
        _prayer = prayerService,
        _audio = playbackService;

  final AppStateRepository _appState;
  final PlaylistRepository _playlists;
  final ScheduleRepository _schedules;
  final SleepRepository _sleep;
  final PrayerService _prayer;
  final AudioPlaybackService _audio;

  final _snapshotController = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _snapshot = const PlaybackSnapshot(state: AppPlaybackState.inactive);
  final _shuffleEngines = <String, ShuffleEngine>{};

  StreamSubscription<PlayerState>? _playerSub;
  Timer? _modeCheckTimer;

  Stream<PlaybackSnapshot> get snapshotStream => _snapshotController.stream;
  PlaybackSnapshot get snapshot => _snapshot;

  void startModeMonitoring() {
    _modeCheckTimer?.cancel();
    _modeCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) => refreshModeState());
  }

  Future<void> initialize() async {
    final active = await _appState.isActive();
    _emit(_snapshot.copyWith(
      state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
    ));
    _playerSub = _audio.playerStateStream.listen(_onPlayerState);
    startModeMonitoring();
  }

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      unawaited(_onClipCompleted());
    }
  }

  Future<void> _onClipCompleted() async {
    if (_snapshot.playlistId == null) {
      await stop();
      return;
    }
    final clips = await _playlists.getClips(_snapshot.playlistId!);
    if (clips.length <= 1) {
      await stop();
      return;
    }
    await playPlaylist(_snapshot.playlistId!);
  }

  Future<void> toggleActive() async {
    final active = await _appState.isActive();
    if (active) {
      await _appState.setActive(false);
      await _audio.stop();
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
    } else {
      await _appState.setActive(true);
      await refreshModeState();
    }
  }

  Future<void> playPlaylist(String playlistId, {bool fromSchedule = false}) async {
    if (!await _canPlay()) return;

    final clips = await _playlists.getClips(playlistId);
    if (clips.isEmpty) return;

    final playlist = await _playlists.getById(playlistId);
    final shuffle = playlist?.shuffleEnabled ?? false;
    final clip = shuffle ? _nextShuffledClip(playlistId, clips) : clips.first;

    if (!_isPlayablePath(clip.filePath)) return;

    try {
      await _audio.playFile(clip.filePath);
    } catch (_) {
      return;
    }

    _emit(_snapshot.copyWith(
      state: fromSchedule ? AppPlaybackState.scheduledPlaying : AppPlaybackState.manualPlaying,
      playlistId: playlistId,
      playlistName: playlist?.name,
      clipTitle: clip.title,
      isPlaying: true,
      shuffleEnabled: shuffle,
      modalVisible: true,
    ));
  }

  bool _isPlayablePath(String path) {
    return !path.startsWith('asset://') && !path.startsWith('demo://');
  }

  Future<void> pause() async {
    await _audio.pause();
    _emit(_snapshot.copyWith(isPlaying: false));
  }

  Future<void> resume() async {
    if (!await _canPlay()) return;
    await _audio.resume();
    _emit(_snapshot.copyWith(isPlaying: true, modalVisible: true));
  }

  Future<void> stop() async {
    await _audio.stop();
    if (await _appState.isActive()) {
      await refreshModeState();
    } else {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
    }
  }

  void dismissModal() {
    if (_snapshot.state == AppPlaybackState.inactive) return;
    _emit(_snapshot.copyWith(modalVisible: false));
  }

  Future<void> toggleShuffle(String playlistId, bool enabled) async {
    await _playlists.setShuffle(playlistId, enabled);
    _emit(_snapshot.copyWith(shuffleEnabled: enabled));
  }

  AudioClip _nextShuffledClip(String playlistId, List<AudioClip> clips) {
    final engine = _shuffleEngines.putIfAbsent(playlistId, ShuffleEngine.new);
    final id = engine.next(clips.map((c) => c.id).toList());
    return clips.firstWhere((c) => c.id == id);
  }

  Future<bool> _canPlay() async {
    if (!await _appState.isActive()) return false;

    final sleep = await _sleep.getActive();
    if (_sleep.isSleepActive(sleep)) {
      _emit(_snapshot.copyWith(state: AppPlaybackState.sleepPaused, isPlaying: false));
      return false;
    }

    final prayer = await _prayer.getCurrentPrayerWindow();
    if (prayer != null) {
      _emit(_snapshot.copyWith(state: AppPlaybackState.prayerPaused, isPlaying: false));
      return false;
    }

    return true;
  }

  Future<void> refreshModeState() async {
    if (!await _appState.isActive()) {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
      return;
    }

    final sleep = await _sleep.getActive();
    if (_sleep.isSleepActive(sleep)) {
      await _audio.pause();
      _emit(_snapshot.copyWith(state: AppPlaybackState.sleepPaused, isPlaying: false));
      return;
    }

    final prayer = await _prayer.getCurrentPrayerWindow();
    if (prayer != null) {
      await _audio.pause();
      _emit(_snapshot.copyWith(state: AppPlaybackState.prayerPaused, isPlaying: false));
      return;
    }

    if (_snapshot.state == AppPlaybackState.sleepPaused ||
        _snapshot.state == AppPlaybackState.prayerPaused) {
      _emit(_snapshot.copyWith(state: AppPlaybackState.activeIdle, isPlaying: false));
    } else if (_snapshot.state == AppPlaybackState.inactive) {
      _emit(_snapshot.copyWith(state: AppPlaybackState.activeIdle));
    }
  }

  void _emit(PlaybackSnapshot snapshot) {
    _snapshot = snapshot;
    _snapshotController.add(snapshot);
  }

  void dispose() {
    _modeCheckTimer?.cancel();
    _playerSub?.cancel();
    _snapshotController.close();
  }
}
