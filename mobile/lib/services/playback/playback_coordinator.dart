import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/entities/audio_clip.dart';
import '../../domain/playback/playback_state.dart';
import '../audio/audio_services.dart';
import '../audio/clip_path_guard.dart';
import '../../l10n/runtime_copy.dart';
import '../prayer/prayer_service.dart';
import '../shuffle/shuffle_engine.dart';

enum ActiveToggleResult { success }

class PlaybackCoordinator {
  PlaybackCoordinator({
    required AppStateRepository appStateRepository,
    required PlaylistRepository playlistRepository,
    required SleepRepository sleepRepository,
    required PrayerService prayerService,
    required AudioPlaybackService playbackService,
  })  : _appState = appStateRepository,
        _playlists = playlistRepository,
        _sleep = sleepRepository,
        _prayer = prayerService,
        _audio = playbackService;

  final AppStateRepository _appState;
  final PlaylistRepository _playlists;
  final SleepRepository _sleep;
  final PrayerService _prayer;
  final AudioPlaybackService _audio;

  final _snapshotController = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _snapshot =
      const PlaybackSnapshot(state: AppPlaybackState.inactive);
  final _shuffleEngines = <String, ShuffleEngine>{};

  StreamSubscription<PlayerState>? _playerSub;
  Timer? _modeCheckTimer;
  String? _pendingScheduledPlaylistId;
  int? _playlistClipIndex;

  /// Called after a scheduled whisper finishes so notifications show the next slot.
  Future<void> Function()? refreshScheduleNotifications;

  /// Replays the current snapshot to every new listener so the UI never misses
  /// the restored "active" state on a cold start (broadcast streams otherwise
  /// drop events emitted before a listener attaches).
  Stream<PlaybackSnapshot> get snapshotStream async* {
    yield _snapshot;
    yield* _snapshotController.stream;
  }

  PlaybackSnapshot get snapshot => _snapshot;

  void startModeMonitoring() {
    _modeCheckTimer?.cancel();
    _modeCheckTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => refreshModeState());
  }

  Future<void> initialize() async {
    final active = await _appState.isActive();
    _audio.onStopRequested = () => unawaited(_deactivateFromNotification());
    _audio.onStopClipRequested = () => unawaited(_finalizeClipStopFromNotification());
    _audio.onPlayRequested = () => _syncPlayingSnapshot(true);
    _audio.onPauseRequested = () => _syncPlayingSnapshot(false);
    _audio.onSkipToNextRequested = () => _skipPlaylistClip(next: true);
    _audio.onSkipToPreviousRequested = () => _skipPlaylistClip(next: false);
    _audio.onClipSessionChanged = () {
      unawaited(refreshScheduleNotifications?.call());
    };
    _emit(
      PlaybackSnapshot(
        state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
        modalVisible: false,
      ),
    );
    // Restore the foreground keep-alive after a cold start if Active.
    if (active) await _audio.enterForeground();
    _playerSub = _audio.playerStateStream.listen(_onPlayerState);
    startModeMonitoring();
  }

  void _syncPlayingSnapshot(bool playing) {
    if (_snapshot.state == AppPlaybackState.inactive) return;
    if (_snapshot.isPlaying == playing) return;
    _emit(_snapshot.copyWith(isPlaying: playing));
  }

  Future<void> _finalizeClipStopFromNotification() async {
    _playlistClipIndex = null;
    final active = await _appState.isActive();
    if (active) {
      _emit(const PlaybackSnapshot(
        state: AppPlaybackState.activeIdle,
        isPlaying: false,
        modalVisible: false,
      ));
      unawaited(refreshModeState());
    } else {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
    }
    await refreshScheduleNotifications?.call();
  }

  Future<void> _skipPlaylistClip({required bool next}) async {
    final playlistId = _snapshot.playlistId;
    if (playlistId == null) return;

    final clips = await _playlists.getClips(playlistId);
    if (clips.length <= 1) {
      await stop();
      return;
    }

    final playlist = await _playlists.getById(playlistId);
    final shuffle = playlist?.shuffleEnabled ?? false;
    final fromSchedule = _snapshot.state == AppPlaybackState.scheduledPlaying;

    if (shuffle) {
      await playPlaylist(playlistId, fromSchedule: fromSchedule);
      return;
    }

    final currentIndex = _playlistClipIndex ?? 0;
    final nextIndex = next
        ? (currentIndex + 1) % clips.length
        : (currentIndex - 1 + clips.length) % clips.length;
    await _playClipAtIndex(
      playlistId,
      clips,
      nextIndex,
      fromSchedule: fromSchedule,
    );
  }

  Future<void> _playClipAtIndex(
    String playlistId,
    List<AudioClip> clips,
    int index, {
    required bool fromSchedule,
  }) async {
    if (index < 0 || index >= clips.length) return;

    final clip = clips[index];
    if (!_isPlayablePath(clip.filePath)) return;

    final playlist = await _playlists.getById(playlistId);

    try {
      await _audio.playFile(
        clip.filePath,
        title: clip.title,
        playlistName: playlist?.name,
        subtitle: fromSchedule
            ? RuntimeCopy.l10n.scheduledWhisper
            : RuntimeCopy.l10n.nowPlaying,
        playlistMode: clips.length > 1,
      );
    } catch (_) {
      return;
    }

    _playlistClipIndex = index;
    _emit(
      _snapshot.copyWith(
        state: fromSchedule
            ? AppPlaybackState.scheduledPlaying
            : AppPlaybackState.manualPlaying,
        playlistId: playlistId,
        playlistName: playlist?.name,
        clipTitle: clip.title,
        isPlaying: true,
        shuffleEnabled: playlist?.shuffleEnabled ?? false,
        modalVisible: false,
      ),
    );
    await refreshScheduleNotifications?.call();
  }

  Future<void> _deactivateFromNotification() async {
    await _appState.setActive(false);
    await _audio.exitForeground();
    _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
  }

  void _onPlayerState(PlayerState state) {
    if (_snapshot.state == AppPlaybackState.manualPlaying ||
        _snapshot.state == AppPlaybackState.scheduledPlaying) {
      final playing = state.playing;
      if (playing != _snapshot.isPlaying &&
          state.processingState != ProcessingState.completed) {
        _emit(_snapshot.copyWith(isPlaying: playing));
      }
    }

    if (state.processingState == ProcessingState.completed) {
      unawaited(_onClipCompleted());
    }
  }

  Future<void> _onClipCompleted() async {
    if (_snapshot.state == AppPlaybackState.scheduledPlaying) {
      await _finishScheduledClip();
      return;
    }

    if (_snapshot.playlistId == null) {
      await _finishManualPreview();
      await _drainPendingScheduled();
      return;
    }

    final clips = await _playlists.getClips(_snapshot.playlistId!);
    if (clips.length <= 1) {
      await stop();
      await _drainPendingScheduled();
      return;
    }
    await playPlaylist(_snapshot.playlistId!);
  }

  Future<void> _finishScheduledClip() async {
    final active = await _appState.isActive();
    _emit(PlaybackSnapshot(
      state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
      isPlaying: false,
      modalVisible: false,
    ));
    await _audio.stop();
    await refreshScheduleNotifications?.call();
    await _drainPendingScheduled();
  }

  Future<void> _finishManualPreview() async {
    final active = await _appState.isActive();
    _emit(PlaybackSnapshot(
      state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
      isPlaying: false,
      modalVisible: false,
    ));
    await _audio.stop();
  }

  Future<void> _drainPendingScheduled() async {
    final next = _pendingScheduledPlaylistId;
    if (next == null) return;
    _pendingScheduledPlaylistId = null;
    await requestScheduledPlay(next);
  }

  /// Called by [ScheduleEngine]. Scheduled whispers take priority over manual
  /// preview/playlist playback — current audio is stopped first.
  /// Returns true when clip playback actually started.
  Future<bool> requestScheduledPlay(String playlistId) async {
    await _interruptForSchedule();
    return playPlaylist(playlistId, fromSchedule: true);
  }

  Future<void> _interruptForSchedule() async {
    if (!_snapshot.isPlaying &&
        _snapshot.state != AppPlaybackState.manualPlaying &&
        _snapshot.state != AppPlaybackState.scheduledPlaying) {
      return;
    }
    await _audio.stop();
    final active = await _appState.isActive();
    _emit(PlaybackSnapshot(
      state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
      isPlaying: false,
      modalVisible: false,
    ));
  }

  Future<ActiveToggleResult> toggleActive() async {
    final active = await _appState.isActive();
    if (active) {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
      await _appState.setActive(false);
      await _audio.exitForeground();
    } else {
      _emit(_snapshot.copyWith(
        state: AppPlaybackState.activeIdle,
        isPlaying: false,
      ));
      await _appState.setActive(true);
      await _activateInBackground();
    }
    return ActiveToggleResult.success;
  }

  Future<void> _activateInBackground() async {
    await _audio.enterForeground();
    await refreshModeState();
    await refreshScheduleNotifications?.call();
  }

  Future<bool> playPlaylist(String playlistId,
      {bool fromSchedule = false}) async {
    if (!fromSchedule && !await _canPlay()) return false;
    if (fromSchedule && !await _appState.isActive()) return false;

    final clips = await _playlists.getClips(playlistId);
    if (clips.isEmpty) return false;

    final playlist = await _playlists.getById(playlistId);
    final shuffle = playlist?.shuffleEnabled ?? false;
    final clip = shuffle ? _nextShuffledClip(playlistId, clips) : clips.first;
    _playlistClipIndex = shuffle ? null : 0;

    if (!_isPlayablePath(clip.filePath)) return false;

    if (fromSchedule) {
      final sleep = await _sleep.getActive();
      if (_sleep.isSleepActive(sleep)) return false;
      final prayer = await _prayer.getCurrentPrayerWindow();
      if (prayer != null) return false;
    }

    try {
      await _audio.playFile(
        clip.filePath,
        title: clip.title,
        playlistName: playlist?.name,
        subtitle: fromSchedule
            ? RuntimeCopy.l10n.scheduledWhisper
            : RuntimeCopy.l10n.nowPlaying,
        playlistMode: clips.length > 1,
      );
    } catch (_) {
      return false;
    }

    _emit(
      _snapshot.copyWith(
        state: fromSchedule
            ? AppPlaybackState.scheduledPlaying
            : AppPlaybackState.manualPlaying,
        playlistId: playlistId,
        playlistName: playlist?.name,
        clipTitle: clip.title,
        isPlaying: true,
        shuffleEnabled: shuffle,
        modalVisible: false,
      ),
    );
    await refreshScheduleNotifications?.call();
    return true;
  }

  /// Plays a single clip on demand (library preview). A manual tap plays
  /// immediately — Sleep/Prayer quiet windows only gate *automatic* playback,
  /// so we don't block the user behind a GPS prayer-time lookup here.
  Future<void> playClip(AudioClip clip) async {
    if (!_isPlayablePath(clip.filePath)) return;

    if (_snapshot.isPlaying) {
      await _audio.stop();
    }

    // Optimistic: show the now-playing sheet instantly for snappy feedback.
    // playlistId is null so completion stops cleanly.
    _emit(PlaybackSnapshot(
      state: AppPlaybackState.manualPlaying,
      playlistName: clip.title,
      clipTitle: clip.title,
      isPlaying: true,
      modalVisible: false,
    ));

    try {
      await _audio.playFile(
        clip.filePath,
        title: clip.title,
        subtitle: RuntimeCopy.l10n.libraryPreview,
      );
    } catch (_) {
      await stop();
      return;
    }
    await refreshScheduleNotifications?.call();
  }

  bool _isPlayablePath(String path) {
    return ClipPathGuard.isAllowed(path);
  }

  Future<void> pause() async {
    await _audio.pause();
    _emit(_snapshot.copyWith(isPlaying: false));
  }

  Future<void> resume() async {
    // Library clip preview does not require the master toggle.
    if (_snapshot.playlistId == null) {
      final path = _audio.currentPath;
      if (path == null) return;
      final atEnd = _audio.player.processingState == ProcessingState.completed;
      if (atEnd) {
        await _audio.playFile(
          path,
          title: _snapshot.clipTitle ?? '',
          subtitle: RuntimeCopy.l10n.libraryPreview,
        );
      } else {
        await _audio.resume();
      }
      _emit(_snapshot.copyWith(isPlaying: true, modalVisible: true));
      return;
    }

    if (!await _canPlay()) return;
    await _audio.resume();
    _emit(_snapshot.copyWith(isPlaying: true, modalVisible: true));
  }

  Future<void> stop() async {
    _playlistClipIndex = null;
    await _audio.stop();
    final active = await _appState.isActive();
    if (active) {
      _emit(const PlaybackSnapshot(
        state: AppPlaybackState.activeIdle,
        isPlaying: false,
        modalVisible: false,
      ));
      unawaited(refreshModeState());
    } else {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
    }
    await refreshScheduleNotifications?.call();
  }

  void dismissModal() {
    if (_snapshot.state == AppPlaybackState.inactive) return;
    _emit(_snapshot.copyWith(modalVisible: false));
  }

  void showModal() {
    if (_snapshot.state == AppPlaybackState.inactive ||
        _snapshot.state == AppPlaybackState.activeIdle) {
      return;
    }
    _emit(_snapshot.copyWith(modalVisible: true));
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
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.sleepPaused, isPlaying: false));
      return false;
    }

    final prayer = await _prayer.getCurrentPrayerWindow();
    if (prayer != null) {
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.prayerPaused, isPlaying: false));
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
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.sleepPaused, isPlaying: false));
      return;
    }

    final prayer = await _prayer.getCurrentPrayerWindow();
    if (prayer != null) {
      await _audio.pause();
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.prayerPaused, isPlaying: false));
      return;
    }

    if (_snapshot.state == AppPlaybackState.sleepPaused ||
        _snapshot.state == AppPlaybackState.prayerPaused) {
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.activeIdle, isPlaying: false));
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
