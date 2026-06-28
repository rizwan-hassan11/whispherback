import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/entities/audio_clip.dart';
import '../../domain/playback/playback_state.dart';
import '../audio/audio_services.dart';
import '../audio/clip_path_guard.dart';
import '../../l10n/runtime_copy.dart';
import '../prayer/adhan_player.dart';
import '../prayer/prayer_service.dart';
import '../playback/active_mode_binding.dart';
import '../shuffle/shuffle_engine.dart';

enum ActiveToggleResult { success }

/// Why a clip failed to play. Drives the message the shell shows in a snackbar
/// so the user always gets feedback after tapping a play button.
enum PlaybackErrorReason {
  /// File path was rejected by [ClipPathGuard] (asset, traversal, wrong ext).
  pathRejected,

  /// Underlying audio player threw — corrupt file, missing codec, or the
  /// `audio_service` foreground session never bound on this device.
  decodeFailed,

  /// User tapped Play on an empty playlist. Surfaces a friendly "add clips
  /// to play" message instead of looking like a silent no-op.
  emptyPlaylist,

  /// User tapped Play on a playlist while the master Active toggle is OFF.
  /// We prompt them to flip it on so scheduled playback works too.
  inactiveToggle,
}

class PlaybackErrorEvent {
  const PlaybackErrorEvent(this.reason, {this.clipTitle});

  final PlaybackErrorReason reason;
  final String? clipTitle;
}

class PlaybackCoordinator {
  PlaybackCoordinator({
    required AppStateRepository appStateRepository,
    required PlaylistRepository playlistRepository,
    required SleepRepository sleepRepository,
    required PrayerService prayerService,
    required AudioPlaybackService playbackService,
    ScheduleRepository? scheduleRepository,
  })  : _appState = appStateRepository,
        _playlists = playlistRepository,
        _sleep = sleepRepository,
        _prayer = prayerService,
        _audio = playbackService,
        _schedules = scheduleRepository;

  final AppStateRepository _appState;
  final PlaylistRepository _playlists;
  final SleepRepository _sleep;
  final PrayerService _prayer;
  final AudioPlaybackService _audio;
  // Optional: used as a belt-and-suspenders last-moment check that the
  // schedule the engine just told us to run hasn't been toggled OFF in the
  // race window between the engine reading the DB and us actually starting
  // audio. Existing tests construct the coordinator without injecting a
  // repository, so this is intentionally nullable.
  final ScheduleRepository? _schedules;

  final _snapshotController = StreamController<PlaybackSnapshot>.broadcast();
  // Broadcasts user-facing playback errors (e.g. corrupt file, blocked path,
  // audio_service init failure). The shell listens and shows a snackbar so a
  // failed tap never appears as a silent no-op.
  final _errorController = StreamController<PlaybackErrorEvent>.broadcast();
  PlaybackSnapshot _snapshot =
      const PlaybackSnapshot(state: AppPlaybackState.inactive);
  final _shuffleEngines = <String, ShuffleEngine>{};

  StreamSubscription<PlayerState>? _playerSub;
  Timer? _modeCheckTimer;
  String? _pendingScheduledPlaylistId;
  String? _pendingScheduledScheduleId;
  int? _playlistClipIndex;
  String? _lastAdhanWindowKey;

  /// True once the user has explicitly tapped pause on the current clip.
  /// Cleared when they explicitly resume, when a new clip starts, or when
  /// playback is stopped. Used to suppress the playlist auto-advance that
  /// would otherwise fire if the underlying clip happened to reach
  /// `completed` between the user's pause tap and the OS actually pausing
  /// the player — observed on short 2-5 s clips on Samsung devices, where
  /// the user perceived "pause triggered next clip play".
  bool _userInitiatedPause = false;

  /// Suppresses the `_userInitiatedPause = true` assignment inside
  /// `_syncPlayingSnapshot(false)` while a SYSTEM pause (sleep mode,
  /// prayer window, etc.) is going through `_handler.pause()`. Without
  /// this, sleep / prayer pauses would arm the suppression sentinel and
  /// the very next natural completion (e.g. of a short clip whose end
  /// raced the system pause) would be treated as a user pause — leaving
  /// playlists stuck on track 1 and scheduled fires never stamping
  /// completion. Set true around the system pause call, reset in
  /// `finally`.
  bool _systemDrivenPauseInFlight = false;

  /// Schedule id behind the currently running scheduled playback (if any).
  /// Lets us stamp `lastFired = completionTime` so the user-configured
  /// interval is measured from the END of playback, not the START.
  String? _activeScheduleId;

  /// Read-only access to the schedule id currently driving playback. The
  /// [ScheduleEngine] uses this to detect when a schedule has been deleted or
  /// disabled mid-playback and needs to be torn down.
  String? get activeScheduleId => _activeScheduleId;

  /// Shuffle flag from the [PlaybackSchedule] that triggered the current run.
  /// We honor this over the playlist's own shuffle setting for the scheduled
  /// session, so toggling shuffle in the schedule builder actually applies.
  bool? _activeScheduleShuffle;

  /// Snapshot of the clip list shown when the user tapped a library clip.
  /// Lets us walk Next/Previous through the Clip Library, not just playlists.
  List<AudioClip> _libraryQueue = const [];
  int _libraryIndex = -1;

  /// Serializes every entry-point that starts new audio. Rapid taps from the
  /// user (and racing schedule fires) used to interleave `stop()` and
  /// `playFile()` calls — sometimes the SECOND call's `stop()` killed the
  /// FIRST call's freshly-started playback, leaving the UI showing a clip
  /// title with no audio. This mutex keeps each play attempt atomic from the
  /// coordinator's POV; the audio_service plugin handles native-side ducking.
  Future<void> _playGate = Future<void>.value();

  /// Hard cap on a single serialized play body. If a play attempt
  /// genuinely hangs (audio session deadlock, native MediaPlayer hung on
  /// decode, etc.) we MUST release the gate so the next user tap doesn't
  /// queue forever — that was the "after a while nothing plays but delete
  /// still works" symptom: delete bypassed the gate, every play attempt
  /// was queued behind a permanently-hung previous gate body.
  ///
  /// 20 seconds is a comfortable upper bound: a healthy playFile finishes
  /// in <2s even on cold Samsung devices, and the 8s setAudioSource cap
  /// inside the handler plus a small margin for surrounding bookkeeping
  /// fits well under this.
  static const _playGateBodyTimeout = Duration(seconds: 20);

  Future<T> _serializePlay<T>(Future<T> Function() body) {
    final previous = _playGate;
    final completer = Completer<T>();
    _playGate = previous
        // Swallow any error from the previous body so the chain itself
        // never enters an unhandled state and starves follow-up plays.
        .then((_) => null, onError: (Object _, StackTrace __) => null)
        .then((_) async {
      try {
        final result =
            await body().timeout(_playGateBodyTimeout, onTimeout: () {
          // The body never finished — return a fallback (typed as T) so
          // the gate can advance. We can't synthesise an arbitrary T here,
          // so let the timeout propagate via a thrown TimeoutException;
          // the catch below will release the completer.
          throw TimeoutException(
            'PlaybackCoordinator: play body did not complete within '
            '$_playGateBodyTimeout — releasing the gate so follow-up '
            'taps are not silently queued forever.',
            _playGateBodyTimeout,
          );
        });
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('PlaybackCoordinator._serializePlay body failed: $e\n$st');
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Called after a scheduled whisper finishes so notifications show the next slot.
  Future<void> Function()? refreshScheduleNotifications;

  /// Invoked when a scheduled clip finishes naturally. Carries the schedule id
  /// of the run that just completed and the wall-clock time it finished so
  /// the engine can update `lastFired` and compute the next slot relative to
  /// playback end (interval = gap after the clip stops, not from when it
  /// started).
  Future<void> Function(String scheduleId, DateTime completedAt)?
      onScheduledPlaybackCompleted;

  /// Replays the current snapshot to every new listener so the UI never misses
  /// the restored "active" state on a cold start (broadcast streams otherwise
  /// drop events emitted before a listener attaches).
  Stream<PlaybackSnapshot> get snapshotStream async* {
    yield _snapshot;
    yield* _snapshotController.stream;
  }

  /// One-shot events for unrecoverable playback failures. Listen from the
  /// app shell to show a user-facing toast — never let a play tap appear as
  /// a silent no-op.
  Stream<PlaybackErrorEvent> get errors => _errorController.stream;

  PlaybackSnapshot get snapshot => _snapshot;

  void startModeMonitoring() {
    _modeCheckTimer?.cancel();
    _modeCheckTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => refreshModeState());
  }

  Future<void> initialize() async {
    final active = await _appState.isActive();
    ActiveModeBinding.instance.attach(_deactivateFromNotification);
    _audio.onStopRequested = () => unawaited(_deactivateFromNotification());
    _audio.onStopClipRequested =
        () => unawaited(_finalizeClipStopFromNotification());
    _audio.onPlayRequested = () => _syncPlayingSnapshot(true);
    _audio.onPauseRequested = () => _syncPlayingSnapshot(false);
    _audio.onSkipToNextRequested = () => _skipPlaylistClip(next: true);
    _audio.onSkipToPreviousRequested = () => _skipPlaylistClip(next: false);
    _audio.onClipSessionChanged = () {
      unawaited(refreshScheduleNotifications?.call());
    };
    // Soft-fail: if `playFile` returns successfully but the native player
    // sits in `idle` / `loading` for >5s without ever reaching a playable
    // state, the handler fires this callback. We surface a snackbar AND
    // tear down the optimistic snapshot so the user doesn't see a
    // mini-player claiming to play when the audio session is wedged.
    // The teardown is fired-and-forgotten: failure to clean up never
    // re-throws to the caller.
    _audio.onPlaybackStartFailure = (title) {
      if (_errorController.isClosed) return;
      _errorController.add(PlaybackErrorEvent(
        PlaybackErrorReason.decodeFailed,
        clipTitle: title,
      ));
      // Only roll the snapshot back if THIS clip is still the active
      // one — by the time the 5s watchdog fires the user may have
      // already tapped another clip that started fine.
      final still =
          _snapshot.isPlaying && (_snapshot.clipTitle == title);
      if (still) {
        unawaited(() async {
          try {
            await stop();
          } catch (_) {}
        }());
      }
    };
    _emit(
      PlaybackSnapshot(
        state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
        modalVisible: false,
      ),
    );
    // Restore the foreground keep-alive after a cold start if Active.
    if (active) await _audio.enterForeground();
    _playerSub = _audio.playerStateStream.listen(
      _onPlayerState,
      onError: (Object e, StackTrace st) {
        // Round 17: an uncaught error in the player state stream was the
        // root cause of "rapid pause/play crashes the app". Silently
        // swallow so the activity stays alive.
        if (kDebugMode) {
          debugPrint('coordinator playerStateStream error (swallowed): $e\n$st');
        }
      },
    );
    startModeMonitoring();
  }

  void _syncPlayingSnapshot(bool playing) {
    if (_snapshot.state == AppPlaybackState.inactive) return;
    if (playing) {
      // Lock-screen / notification "play" tap should clear the user-paused
      // sentinel so the next completion event behaves like a normal end-of-
      // clip and auto-advances when appropriate.
      _userInitiatedPause = false;
    } else if (!_systemDrivenPauseInFlight) {
      // This callback fires for any `_handler.pause()` invocation, which
      // includes both genuine user pauses (lock-screen button, in-app
      // pause) AND coordinator-driven system pauses (sleep mode entering,
      // prayer window starting). Only the user-driven ones should arm the
      // suppression sentinel — `_systemDrivenPauseInFlight` is the flag we
      // set around the system-pause call sites to opt out.
      _userInitiatedPause = true;
    }
    if (_snapshot.isPlaying == playing) return;
    _emit(_snapshot.copyWith(isPlaying: playing));
  }

  /// Wraps a system-driven pause (sleep mode, prayer pause, scheduled
  /// interrupt) so the `onPauseRequested` callback in `_handler.pause()`
  /// does NOT arm the `_userInitiatedPause` sentinel. Without this, the
  /// next natural clip completion after the system pause would be
  /// swallowed as if the user had paused — collapsing playlist auto-
  /// advance and stamping no scheduled completion.
  Future<void> _systemPause() async {
    _systemDrivenPauseInFlight = true;
    try {
      await _audio.pause();
    } finally {
      _systemDrivenPauseInFlight = false;
    }
  }

  Future<void> _finalizeClipStopFromNotification() async {
    _playlistClipIndex = null;
    _userInitiatedPause = false;
    // System-stop from the media notification ≠ natural completion.
    _activeScheduleId = null;
    _activeScheduleShuffle = null;
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

  Future<void> skipNext() => _guardedSkip(next: true);
  Future<void> skipPrevious() => _guardedSkip(next: false);

  /// Wraps `_skipPlaylistClip` in a try/catch + error event so a thrown
  /// PlatformException from the native player never propagates out of a
  /// skip tap. The user perceives an unhandled throw as "app crashed when
  /// I pressed next" — which is the exact symptom they reported on the
  /// mini-player and modal controls.
  Future<void> _guardedSkip({required bool next}) async {
    try {
      await _skipPlaylistClip(next: next);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('skip${next ? 'Next' : 'Previous'} failed: $e\n$st');
      }
      if (!_errorController.isClosed) {
        _errorController.add(PlaybackErrorEvent(
          PlaybackErrorReason.decodeFailed,
          clipTitle: _snapshot.clipTitle,
        ));
      }
    }
  }

  Future<void> _skipPlaylistClip({required bool next}) async {
    // Explicit skip is an unambiguous user intent to move forward/back, even
    // if they had previously tapped pause. Clear the sentinel so the next
    // natural completion in the new clip behaves normally.
    _userInitiatedPause = false;
    final playlistId = _snapshot.playlistId;
    if (playlistId == null) {
      // Library-queue context: walk through the currently shown clip list.
      if (_libraryQueue.length <= 1) {
        // Single clip — restart from the top so the button still feels alive
        // instead of silently doing nothing.
        if (_libraryQueue.isEmpty) return;
        await _audio.seek(Duration.zero);
        await _audio.resume();
        return;
      }
      final currentIndex = _libraryIndex < 0 ? 0 : _libraryIndex;
      final nextIndex = next
          ? (currentIndex + 1) % _libraryQueue.length
          : (currentIndex - 1 + _libraryQueue.length) % _libraryQueue.length;
      _libraryIndex = nextIndex;
      final clip = _libraryQueue[nextIndex];
      await playClip(clip, queue: _libraryQueue);
      return;
    }

    final clips = await _playlists.getClips(playlistId);
    if (clips.length <= 1) {
      // Single-clip playlist: replay from the top instead of stopping —
      // matches user expectation for a "next" tap on a one-track playlist.
      if (clips.isEmpty) return;
      _playlistClipIndex = 0;
      await _playClipAtIndex(
        playlistId,
        clips,
        0,
        fromSchedule: _snapshot.state == AppPlaybackState.scheduledPlaying,
      );
      return;
    }

    final playlist = await _playlists.getById(playlistId);
    final shuffle = playlist?.shuffleEnabled ?? false;
    final fromSchedule = _snapshot.state == AppPlaybackState.scheduledPlaying;

    if (shuffle) {
      // _skipPlaylistClip is called from inside an already-running play, so
      // re-enter the internal (non-locking) path; the public playPlaylist
      // would deadlock on the same gate.
      await _playPlaylistInternal(playlistId, fromSchedule: fromSchedule);
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
    await AdhanPlayer.instance.stop();
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
    // Race-window mitigation: on slow devices, just_audio's completion
    // event can land 1-2 frames BEFORE the user's pause tap reaches
    // `coordinator.pause()`. The sentinel below would still read false
    // even though the user is mid-pause-gesture. Yield once to the event
    // loop so any in-flight pause tap has a chance to land + flip the
    // sentinel BEFORE we read it. This is a single microtask delay
    // (effectively zero on a healthy device) and is the cheapest known
    // fix for the QA "pause triggers next clip" reproduction on Samsung
    // mid-range devices.
    await Future<void>.delayed(Duration.zero);

    // If the user explicitly paused this clip, treat any completion event
    // that lands after the pause-tap as "finished at the paused position"
    // rather than as a natural end-of-clip — otherwise the auto-advance
    // below would fire the next clip and the user perceives it as
    // "tapping pause skipped to the next clip". They must explicitly tap
    // play or skip to move on.
    if (_userInitiatedPause) {
      _userInitiatedPause = false;
      // Park the position at zero so a later resume restarts cleanly and
      // doesn't immediately re-fire a completion event.
      try {
        await _audio.seek(Duration.zero);
      } catch (_) {}
      _emit(_snapshot.copyWith(isPlaying: false));
      return;
    }

    if (_snapshot.state == AppPlaybackState.scheduledPlaying) {
      await _finishScheduledClip();
      return;
    }

    if (_snapshot.playlistId == null) {
      await _finishManualPreview();
      await _drainPendingScheduled();
      return;
    }

    final playlistId = _snapshot.playlistId!;
    final clips = await _playlists.getClips(playlistId);
    if (clips.isEmpty) {
      await stop();
      await _drainPendingScheduled();
      return;
    }

    final playlist = await _playlists.getById(playlistId);
    final shuffle = playlist?.shuffleEnabled ?? false;

    if (shuffle) {
      // Shuffle re-draws from ShuffleEngine which guarantees no repeats until
      // the cycle completes. We come from the audio_service completion
      // callback (already inside the player lifecycle), so use the internal
      // non-locking entry to avoid deadlocking on the play gate.
      await _playPlaylistInternal(playlistId);
      return;
    }

    // Sequential playlist: advance to the NEXT clip. The previous code called
    // playPlaylist(...) which always picked clips.first — so a 3-clip playlist
    // would replay track 1 forever instead of moving to track 2. This is the
    // P0 client-visible bug. We also skip over any clip whose file is gone
    // (sandbox corruption, deleted-on-disk) instead of stalling.
    final lastIndex = _playlistClipIndex ?? 0;
    final startIndex = (lastIndex + 1) % clips.length;
    final endIndex = await _advanceToNextPlayable(
      playlistId,
      clips,
      startIndex,
      fromSchedule: false,
    );
    if (endIndex == null) {
      // No playable clips remain (every file is missing/decode-failed). Stop
      // gracefully and tell the user so they don't think audio just died.
      await stop();
      if (!_errorController.isClosed) {
        _errorController.add(const PlaybackErrorEvent(
          PlaybackErrorReason.decodeFailed,
        ));
      }
    }
  }

  /// Walks [clips] starting at [startIndex] forward and plays the first one
  /// whose path is allowed AND whose `playFile` succeeds. Returns the played
  /// index, or null if the entire playlist is unplayable.
  ///
  /// Wraps once around the list so a corrupted clip near the end doesn't
  /// silently end the session.
  Future<int?> _advanceToNextPlayable(
    String playlistId,
    List<AudioClip> clips,
    int startIndex, {
    required bool fromSchedule,
  }) async {
    final playlist = await _playlists.getById(playlistId);
    final visited = <int>{};
    var index = startIndex;
    while (visited.add(index)) {
      if (index < 0 || index >= clips.length) break;
      final clip = clips[index];
      if (_isPlayablePath(clip.filePath)) {
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
          return index;
        } catch (_) {
          // Fall through to next index.
        }
      }
      index = (index + 1) % clips.length;
    }
    return null;
  }

  Future<void> _finishScheduledClip() async {
    final completedScheduleId = _activeScheduleId;
    _activeScheduleId = null;
    _activeScheduleShuffle = null;
    final active = await _appState.isActive();
    _emit(PlaybackSnapshot(
      state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
      isPlaying: false,
      modalVisible: false,
    ));
    await _audio.stop();
    if (completedScheduleId != null) {
      // Stamp completion *before* refreshing notifications so the engine's
      // "next slot" math uses the post-playback timestamp and the upcoming
      // banner reflects the correct interval-from-end.
      await onScheduledPlaybackCompleted?.call(
        completedScheduleId,
        DateTime.now(),
      );
    }
    await refreshScheduleNotifications?.call();
    await _drainPendingScheduled();
  }

  Future<void> _finishManualPreview() async {
    _userInitiatedPause = false;
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
    final pendingScheduleId = _pendingScheduledScheduleId;
    _pendingScheduledPlaylistId = null;
    _pendingScheduledScheduleId = null;
    await requestScheduledPlay(next, scheduleId: pendingScheduleId);
  }

  /// Called by [ScheduleEngine]. Scheduled whispers take priority over manual
  /// preview/playlist playback — current audio is stopped first.
  /// Returns true when clip playback actually started.
  ///
  /// [scheduleId] is the id of the [PlaybackSchedule] that triggered this run.
  /// We hold it so that when playback finishes naturally, we can fire
  /// [onScheduledPlaybackCompleted] with the actual completion timestamp and
  /// the engine can measure the next interval from playback END (not START).
  ///
  /// [shuffle] is the schedule's own shuffle setting; when provided it
  /// overrides the playlist's shuffle flag for this run only.
  /// Re-enters the audio_service foreground binding so a subsequent
  /// `requestScheduledPlay` is guaranteed to talk to a live media session.
  /// Idempotent — `_audio.enterForeground` is a no-op when the binding
  /// is already up. Used by `ScheduleEngine` immediately before each
  /// fire so an OS-reclaimed FG service can't silently swallow the play.
  Future<void> ensureForegroundForSchedule() async {
    if (!await _appState.isActive()) return;
    try {
      await _audio.enterForeground();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ensureForegroundForSchedule: enterForeground failed: '
            '$e\n$st');
      }
    }
  }

  Future<bool> requestScheduledPlay(
    String playlistId, {
    String? scheduleId,
    bool? shuffle,
  }) {
    return _serializePlay(() async {
      // Belt-and-suspenders disable check at the very last moment before
      // we touch audio_service. Between the engine reading the schedule
      // and this body running inside the play-gate, the user may have
      // toggled the schedule OFF (or the app-wide Active toggle OFF) —
      // honor that even though the engine already passed its own check.
      // We deliberately use the cheaper `getForPlaylist` (single-row
      // query) instead of `getAll` so this extra check inside the play
      // gate stays sub-millisecond and never throttles legitimate fires.
      if (!await _appState.isActive()) return false;
      final schedRepo = _schedules;
      if (scheduleId != null && schedRepo != null) {
        final fresh = await schedRepo.getForPlaylist(playlistId);
        // If the row vanished or its id no longer matches, the user has
        // either deleted the schedule or replaced it — abort. Otherwise
        // honor the live enabled flag.
        if (fresh == null || fresh.id != scheduleId || !fresh.enabled) {
          return false;
        }
      }
      await _interruptForSchedule();
      _activeScheduleId = scheduleId;
      _activeScheduleShuffle = shuffle;
      // Use try/finally so a throw inside `_playPlaylistInternal` always
      // clears the active-schedule pointer. Previously a thrown error
      // (rare, but possible from a PlatformException deep in the audio
      // handler) would leave `_activeScheduleId` set, and the engine
      // would never re-enter the schedule for a fresh attempt — user
      // perceived as "schedule disappeared from the next-up list".
      try {
        final started =
            await _playPlaylistInternal(playlistId, fromSchedule: true);
        if (!started) {
          _activeScheduleId = null;
          _activeScheduleShuffle = null;
        }
        return started;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('requestScheduledPlay: internal play threw: $e\n$st');
        }
        _activeScheduleId = null;
        _activeScheduleShuffle = null;
        if (!_errorController.isClosed) {
          _errorController.add(const PlaybackErrorEvent(
            PlaybackErrorReason.decodeFailed,
          ));
        }
        return false;
      }
    });
  }

  Future<void> _interruptForSchedule() async {
    _userInitiatedPause = false;
    if (!_snapshot.isPlaying &&
        _snapshot.state != AppPlaybackState.manualPlaying &&
        _snapshot.state != AppPlaybackState.scheduledPlaying) {
      _activeScheduleId = null;
      _activeScheduleShuffle = null;
      return;
    }
    // The current scheduled run never finished — drop the tracking so the
    // interrupted schedule doesn't get a phantom completion timestamp.
    _activeScheduleId = null;
    _activeScheduleShuffle = null;
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
      _userInitiatedPause = false;
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
      await _appState.setActive(false);
      await _audio.exitForeground();
      await AdhanPlayer.instance.stop();
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
    // CRITICAL ORDER: post the Flutter ongoing notification FIRST so the
    // user immediately sees "WhisperBack is active" — even if the
    // audio_service silent keep-alive below fails or takes time to
    // bind. Previously the order was reversed: we'd attempt to enter
    // the foreground service (which on Vivo / Infinix sometimes never
    // commits its own notification) and ONLY THEN refresh the Flutter
    // status card. On those devices the user saw NO notification at
    // all between the toggle tap and the first delayed retry.
    //
    // Each call is independently try/caught so a single failure can
    // never block the others.
    try {
      await refreshScheduleNotifications?.call();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '_activateInBackground: initial notif refresh failed: $e\n$st');
      }
    }
    try {
      await _audio.enterForeground();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '_activateInBackground: enterForeground failed: $e\n$st');
      }
    }
    try {
      await refreshModeState();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '_activateInBackground: refreshModeState failed: $e\n$st');
      }
    }
    // Re-sync notifications AFTER keep-alive so the status card reflects
    // whichever path actually succeeded.
    try {
      await refreshScheduleNotifications?.call();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '_activateInBackground: final notif refresh failed: $e\n$st');
      }
    }
  }

  Future<bool> playPlaylist(String playlistId, {bool fromSchedule = false}) {
    return _serializePlay(
      () => _playPlaylistInternal(playlistId, fromSchedule: fromSchedule),
    );
  }

  Future<bool> _playPlaylistInternal(String playlistId,
      {bool fromSchedule = false}) async {
    if (!fromSchedule) {
      if (!await _canPlay()) {
        // _canPlay() may already have emitted a sleep/prayer snapshot. If
        // it just returned false because Active is OFF, surface a snackbar
        // so the user doesn't think the Play button is broken — silent
        // gating was the exact "playlist won't play but delete works" QA
        // report. We only emit when the *reason* is the active toggle
        // (sleep/prayer have their own dedicated banners on the home
        // screen and the modal).
        final isActive = await _appState.isActive();
        if (!isActive && !_errorController.isClosed) {
          _errorController.add(const PlaybackErrorEvent(
            PlaybackErrorReason.inactiveToggle,
          ));
        }
        return false;
      }
    }
    if (fromSchedule && !await _appState.isActive()) return false;

    final clips = await _playlists.getClips(playlistId);
    if (clips.isEmpty) {
      // Empty playlist tap from the UI should never look like a silent no-op.
      // Scheduled fires intentionally do NOT surface this — the schedule engine
      // logs it; user-visible toasts during background ticks would be noisy.
      if (!fromSchedule && !_errorController.isClosed) {
        _errorController.add(const PlaybackErrorEvent(
          PlaybackErrorReason.emptyPlaylist,
        ));
      }
      return false;
    }

    final playlist = await _playlists.getById(playlistId);
    // The schedule's own shuffle flag wins for scheduled fires (so toggling
    // shuffle in the schedule builder actually takes effect), then the
    // playlist's own setting is used as the fallback. Previously the
    // schedule-side shuffle flag was effectively ignored.
    final shuffle = (fromSchedule && _activeScheduleShuffle != null)
        ? _activeScheduleShuffle!
        : (playlist?.shuffleEnabled ?? false);
    final clip = shuffle ? _nextShuffledClip(playlistId, clips) : clips.first;
    _playlistClipIndex = shuffle ? null : 0;
    _libraryQueue = const [];
    _libraryIndex = -1;
    // Starting a brand-new playlist clears any "user paused" sentinel from
    // a prior session — otherwise the very first natural completion in the
    // new playlist would be swallowed and the auto-advance would never run.
    _userInitiatedPause = false;

    if (!_isPlayablePath(clip.filePath)) {
      if (!fromSchedule && !_errorController.isClosed) {
        _errorController.add(PlaybackErrorEvent(
          PlaybackErrorReason.pathRejected,
          clipTitle: clip.title,
        ));
      }
      return false;
    }

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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('playPlaylist: playFile failed: $e\n$st');
      }
      // ALWAYS surface the decode failure, even for fromSchedule, so the
      // user gets a snackbar instead of "I set a schedule and nothing
      // happened at the scheduled time". The schedule engine will roll
      // back the stamp on its own (it sees the false return).
      if (!_errorController.isClosed) {
        _errorController.add(PlaybackErrorEvent(
          PlaybackErrorReason.decodeFailed,
          clipTitle: clip.title,
        ));
      }
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
  ///
  /// [queue] is the ordered list of clips currently shown to the user (e.g. the
  /// filtered Clip Library). When provided, Next/Previous on the mini-player
  /// and modal walk this list. Pass `[clip]` (or omit) for a true single play.
  Future<void> playClip(AudioClip clip, {List<AudioClip>? queue}) {
    // Run through the serialization gate so rapid taps queue cleanly instead
    // of racing each other and orphaning a half-started clip.
    return _serializePlay(() => _playClipInternal(clip, queue: queue));
  }

  Future<void> _playClipInternal(AudioClip clip,
      {List<AudioClip>? queue}) async {
    if (!_isPlayablePath(clip.filePath)) {
      // Path was rejected by ClipPathGuard — most often a stale row whose
      // file was deleted, or a clip recorded by an older app version stored
      // outside the sandbox. Notify the shell so the user gets a toast.
      if (!_errorController.isClosed) {
        _errorController.add(PlaybackErrorEvent(
          PlaybackErrorReason.pathRejected,
          clipTitle: clip.title,
        ));
      }
      return;
    }

    if (_snapshot.isPlaying) {
      // CRITICAL: never let a pre-flight stop kill the whole play tap. On
      // some Samsung / Vivo devices a fresh boot can leave the previous
      // session in a half-bound state, and `_audio.stop()` throws a
      // PlatformException. The user perceives this as "tapping play
      // crashed the app". We swallow and proceed — the upcoming
      // `setAudioSource` will overwrite whatever the player had.
      try {
        await _audio.stop();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('playClip: pre-flight stop failed (continuing): $e\n$st');
        }
      }
    }

    _libraryQueue =
        (queue == null || queue.isEmpty) ? <AudioClip>[clip] : queue;
    _libraryIndex = _libraryQueue.indexWhere((c) => c.id == clip.id);
    if (_libraryIndex < 0) _libraryIndex = 0;
    _userInitiatedPause = false;

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
        playlistMode: _libraryQueue.length > 1,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('playClip: playFile failed: $e\n$st');
      }
      // Roll back the optimistic snapshot and let the shell warn the user
      // instead of failing silently — this was the client-reported "recorded
      // a clip, tried to play, nothing happened" case on Samsung devices
      // where the audio_service session sometimes never binds. Use a
      // guarded stop so a follow-up failure can't propagate up to the UI.
      try {
        await stop();
      } catch (_) {}
      if (!_errorController.isClosed) {
        _errorController.add(PlaybackErrorEvent(
          PlaybackErrorReason.decodeFailed,
          clipTitle: clip.title,
        ));
      }
      return;
    }
    // Best-effort: failure to refresh the schedule notifications must not
    // crash the play tap. The notification will eventually self-correct on
    // the next engine tick or app resume.
    try {
      await refreshScheduleNotifications?.call();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('playClip: schedule notif refresh failed: $e\n$st');
      }
    }
  }

  /// True when the user is in any clip-playing context.
  ///
  /// The buttons are ALWAYS shown while a clip is playing, even on a
  /// single-clip preview or a one-track playlist. In a single-clip context
  /// tapping next/previous restarts the clip from `Duration.zero` (handled
  /// by `_skipPlaylistClip` and the seek+resume path) — that feels like a
  /// natural "restart" instead of a broken button.
  ///
  /// QA history: Round 6 hid these buttons for single-clip queues to fix
  /// a Samsung lock-screen "pause routed through long-press fast-forward"
  /// regression. That fix mis-targeted the in-app modal too. The lock
  /// screen action routing was actually fixed by overriding `seekForward`
  /// / `seekBackward` / `fastForward` / `rewind` in the audio handler
  /// (`SeekHandler` mixin) — so the in-app skip buttons can safely show
  /// for every playback context. The new "I imported one clip and there
  /// are no NEXT/PREV buttons" QA report confirms users expect to see
  /// them and tap to restart.
  bool get canSkipClips {
    final inPlayback = _snapshot.state == AppPlaybackState.manualPlaying ||
        _snapshot.state == AppPlaybackState.scheduledPlaying;
    return inPlayback;
  }

  bool _isPlayablePath(String path) {
    return ClipPathGuard.isAllowed(path);
  }

  /// Round 15: serialize pause/resume so rapid taps NEVER race the native
  /// player. Without this gate, tapping pause→resume→pause→resume within
  /// a few hundred milliseconds queues up overlapping `_player.pause()`
  /// / `_player.play()` / `AudioSession.setActive()` calls. Each
  /// individual call is safe, but the just_audio + audio_session
  /// combination on Samsung One UI / Vivo Funtouch can throw
  /// `PlatformException("(-38) MediaPlayerNative")` when 3+ state
  /// changes are in flight at once — that PlatformException then
  /// surfaces through the `playbackEventStream` listener and crashes
  /// the audio_service onError plumbing on certain firmware revisions.
  /// Serialization ensures we only ever have ONE state-change in
  /// flight at a time.
  Future<void> _pauseResume = Future<void>.value();

  Future<T> _serializePauseResume<T>(Future<T> Function() body) {
    final previous = _pauseResume;
    final completer = Completer<T>();
    _pauseResume = previous
        .then((_) => null, onError: (Object _, StackTrace __) => null)
        .then((_) async {
      try {
        // Hard cap so a hung native call cannot starve future taps.
        final result =
            await body().timeout(const Duration(seconds: 4), onTimeout: () {
          throw TimeoutException(
            'pause/resume: native call exceeded 4s — releasing gate '
            'so the next tap can proceed.',
            const Duration(seconds: 4),
          );
        });
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'PlaybackCoordinator._serializePauseResume body failed: $e\n$st');
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> pause() {
    return _serializePauseResume(() async {
      // Mark BEFORE the await so any completion event that the player
      // races to emit between the user's tap and `_player.pause()`
      // actually landing is treated as "paused at the end" rather
      // than "auto-advance to next clip".
      _userInitiatedPause = true;
      // Optimistic UI flip first so the user sees their pause take
      // effect immediately even if the native player call is slow /
      // throws.
      _emit(_snapshot.copyWith(isPlaying: false));
      try {
        await _audio.pause();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'pause: _audio.pause failed (UI already updated): $e\n$st');
        }
      }
    });
  }

  /// Pauses the current clip AND hides the mini-player + modal — but does
  /// NOT stop the underlying audio_service session. This is what the
  /// cross icon on the mini-player / modal calls.
  ///
  /// User contract (from the QA report verbatim): "the cross icon should
  /// PAUSE the clip and then hide the spotify-styled bar. When any clip
  /// is clicked again or replayed/resumed, the bar should become visible
  /// again. The cross only hides — it does not delete the playback
  /// session."
  ///
  /// Implementation:
  ///   1. Pause the native player (`_audio.pause()`) — the clip's
  ///      position is preserved. This is the same code path as the
  ///      mini-player's pause button.
  ///   2. Emit a snapshot with the SAME clip metadata but `state:
  ///      activeIdle` (or `inactive` if not Active) so both the mini-
  ///      player visibility check (`state == manualPlaying ||
  ///      scheduledPlaying`) and the modal's `modalVisible` check
  ///      both transition to "hidden".
  ///   3. Do NOT call `_audio.stop()`, `super.stop()`, or any teardown.
  ///      The next `playClip` / `playPlaylist` / schedule fire re-emits
  ///      `manualPlaying` / `scheduledPlaying` and the mini-player re-
  ///      appears automatically.
  ///
  /// Why we no longer call `_audio.stop()` from this path:
  ///   * `_audio.stop()` resolves to `_handler.stopClip()` which clears
  ///     the lock-screen media notification. The user reported that
  ///     after dismissing, tapping a clip again left the player hidden
  ///     and only re-appeared when they tapped Pause on the (now-stale)
  ///     lock-screen card. The state machine was confused because the
  ///     `stopClip` teardown ran but the player's `_playingClip` flag
  ///     left a stale window. Skipping the teardown entirely sidesteps
  ///     all of that.
  Future<void> dismissPlayer() {
    // Round 17: serialize through the same pause/resume gate so a rapid
    // pause → cross → cross → play sequence cannot have overlapping
    // `_audio.pause()` calls in flight. Previously the dismiss path
    // bypassed the serializer and the user's "crashes on multiple
    // pause/resume + cross icon" report traced to native player
    // state-change races between the gated `pause()`/`resume()` and
    // the un-gated `dismissPlayer()`.
    return _serializePauseResume(() async {
      bool wasActive = false;
      try {
        wasActive = await _appState.isActive();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('dismissPlayer: isActive lookup failed: $e\n$st');
        }
      }

      _emit(PlaybackSnapshot(
        state:
            wasActive ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
        isPlaying: false,
        modalVisible: false,
      ));

      _userInitiatedPause = true;
      try {
        await _audio.pause();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('dismissPlayer: _audio.pause failed: $e\n$st');
        }
      }

      try {
        await _audio.hideClipMediaNotification();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'dismissPlayer: hideClipMediaNotification failed: $e\n$st');
        }
      }

      try {
        await refreshScheduleNotifications?.call();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('dismissPlayer: notif refresh failed: $e\n$st');
        }
      }
    });
  }

  Future<void> resume() {
    return _serializePauseResume(() async {
      _userInitiatedPause = false;
      // Optimistic UI flip first — the user expects the play icon to
      // flip to pause the instant they tap. We roll back below if the
      // native call fails. CRITICAL: do NOT force `modalVisible: true`.
      // The QA report "I tap pause, the detail popup opens, I tap
      // resume and everything disappears" was exactly this bug —
      // `resume` was forcing the modal open, the modal's own dismiss
      // action then ran `dismissModal()` which set `modalVisible:
      // false`, and the mini-player check `snapshot.modalVisible` was
      // satisfied by the brief `true` window so it never re-attached.
      // Preserve the user's current modal visibility instead — they
      // keep the mini-player if they were on it, or the modal if they
      // were in it.
      final previous = _snapshot;
      _emit(_snapshot.copyWith(isPlaying: true));

      try {
        // Library clip preview does not require the master toggle.
        if (_snapshot.playlistId == null) {
          final path = _audio.currentPath;
          if (path == null) {
            // Nothing to resume — restore the previous snapshot so the
            // UI doesn't lie about being playing.
            _emit(previous);
            return;
          }
          final atEnd =
              _audio.player.processingState == ProcessingState.completed;
          if (atEnd) {
            await _audio.playFile(
              path,
              title: _snapshot.clipTitle ?? '',
              subtitle: RuntimeCopy.l10n.libraryPreview,
            );
          } else {
            await _audio.resume();
          }
          return;
        }

        if (!await _canPlay()) {
          _emit(previous);
          return;
        }
        await _audio.resume();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('resume: failed, rolling back snapshot: $e\n$st');
        }
        _emit(previous);
        if (!_errorController.isClosed) {
          _errorController.add(PlaybackErrorEvent(
            PlaybackErrorReason.decodeFailed,
            clipTitle: previous.clipTitle,
          ));
        }
      }
    });
  }

  Future<void> stop() async {
    _playlistClipIndex = null;
    _libraryQueue = const [];
    _libraryIndex = -1;
    _userInitiatedPause = false;
    // User-initiated stop must not count as a "successful completion": skip
    // the interval-from-end stamp so the next slot still fires on its grid.
    _activeScheduleId = null;
    _activeScheduleShuffle = null;

    // Optimistically hide the player UI BEFORE waiting on audio_service. This
    // prevents the modal/mini-player from flashing 00:00 frames while the
    // background player tears down, and avoids any silent keep-alive position
    // stream events from rendering after the user hit Stop.
    bool wasActive = false;
    try {
      wasActive = await _appState.isActive();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('stop: isActive lookup failed (assuming inactive): $e\n$st');
      }
    }
    _emit(PlaybackSnapshot(
      state:
          wasActive ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
      isPlaying: false,
      modalVisible: false,
    ));

    // CRITICAL: each external call is independently try/caught so a
    // failure in one path never aborts the stop sequence. The user
    // tapped the cross icon on the modal expecting silence + an
    // immediate UI dismiss; on Samsung One UI / Vivo, a half-bound
    // audio_service session can throw a PlatformException from
    // `_audio.stop()` that would otherwise propagate up to the InkWell
    // tap handler and the user perceived this as "the app crashed on
    // close". The optimistic snapshot above already hid the UI, so
    // even if every cleanup call below throws, the user-visible
    // state is correct.
    try {
      await _audio.stop();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('stop: _audio.stop failed: $e\n$st');
      }
    }
    try {
      await AdhanPlayer.instance.stop();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('stop: AdhanPlayer.stop failed: $e\n$st');
      }
    }

    if (wasActive) {
      // refreshModeState does sleep / prayer / adhan I/O — failures must
      // never propagate to the original cross-icon tap. Even `unawaited`
      // doesn't help if the future throws synchronously inside the
      // first `await`; route through a guarded helper.
      unawaited(() async {
        try {
          await refreshModeState();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('stop: refreshModeState failed: $e\n$st');
          }
        }
      }());
    }
    try {
      await refreshScheduleNotifications?.call();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('stop: schedule notif refresh failed: $e\n$st');
      }
    }
  }

  void dismissModal() {
    if (_snapshot.state == AppPlaybackState.inactive) return;
    _emit(_snapshot.copyWith(modalVisible: false));
  }

  /// Seeks the current clip to [position]. Silently no-ops when there is no
  /// active clip (e.g. activeIdle keep-alive) to avoid scrubbing the silent
  /// loop and breaking the foreground service.
  Future<void> seek(Duration position) async {
    if (_snapshot.state != AppPlaybackState.manualPlaying &&
        _snapshot.state != AppPlaybackState.scheduledPlaying) {
      return;
    }
    if (position.isNegative) position = Duration.zero;
    await _audio.seek(position);
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
    final active = await _appState.isActive();

    // Adhan voice is decoupled from the master Active toggle so users still
    // hear the call to prayer even when WhisperBack whispers are off.
    final prayer = await _prayer.getCurrentPrayerWindow();
    if (prayer != null && await _prayer.adhanEnabled()) {
      final key = '${prayer.name}-${prayer.start.toIso8601String()}';
      if (_lastAdhanWindowKey != key) {
        _lastAdhanWindowKey = key;
        unawaited(AdhanPlayer.instance.playFor(key));
      }
    }

    if (!active) {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
      return;
    }

    final sleep = await _sleep.getActive();
    if (_sleep.isSleepActive(sleep)) {
      await _systemPause();
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.sleepPaused, isPlaying: false));
      return;
    }

    if (prayer != null) {
      await _systemPause();
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
    // Guard against `add` on a closed controller (happens if dispose
    // races with a deferred system callback). Without this, a single
    // post-dispose emit throws StateError on the user's tap — which
    // bubbles out as "app crashed" on the cross icon, even though
    // every other path is try/caught.
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void dispose() {
    _modeCheckTimer?.cancel();
    _playerSub?.cancel();
    _snapshotController.close();
    _errorController.close();
  }
}
