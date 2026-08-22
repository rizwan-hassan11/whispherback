import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/feature_flags.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/entities/audio_clip.dart';
import '../../domain/entities/playback_schedule.dart';
import '../../domain/playback/playback_state.dart';
import '../audio/audio_services.dart';
import '../audio/clip_path_guard.dart';
import '../../l10n/runtime_copy.dart';
import '../platform/keep_alive_service.dart';
import '../prayer/adhan_player.dart';
import '../prayer/prayer_service.dart';
import '../playback/active_mode_binding.dart';
import '../scheduler/native_alarms_bridge.dart';
import '../scheduler/schedule_last_fired_store.dart';
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
  StreamSubscription<NativePlaybackSnapshot>? _nativePlaybackSub;
  Timer? _modeCheckTimer;
  String? _pendingScheduledPlaylistId;
  String? _pendingScheduledScheduleId;
  int? _playlistClipIndex;

  /// In-memory clip list for the active playlist so next/prev never hit SQLite.
  List<AudioClip> _playlistClipCache = const [];
  String? _lastAdhanWindowKey;

  /// True while the visible mini-player snapshot is owned by the native
  /// scheduled-playback service (Round 22). When true, `pause()` /
  /// `resume()` / `dismissPlayer()` route through [NativeAlarmsBridge]
  /// instead of `_audio` (just_audio), because that's the player actually
  /// emitting sound.
  bool _nativeScheduledActive = false;

  /// True once the user has explicitly tapped pause on the current clip.
  /// Cleared when they explicitly resume, when a new clip starts, or when
  /// playback is stopped. Used to suppress the playlist auto-advance that
  /// would otherwise fire if the underlying clip happened to reach
  /// `completed` between the user's pause tap and the OS actually pausing
  /// the player — observed on short 2-5 s clips on Samsung devices, where
  /// the user perceived "pause triggered next clip play".
  bool _userInitiatedPause = false;

  /// Bumped on every skip / new `playFile` so a stale `ProcessingState.completed`
  /// from the previous source (emitted during `setAudioSource` swaps) cannot
  /// tear down the mini-player or jump ahead an extra track. QA: "tap next on
  /// last clip hides the bar instead of wrapping to the first".
  int _playbackGeneration = 0;

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

  /// Single FIFO queue for every user-facing transport action: play, skip,
  /// pause, resume, dismiss. Separate skip / pause / play gates used to run
  /// IN PARALLEL — skip could be mid-playFile while pause ran on another
  /// gate, producing "I tapped next, nothing happened, then pause started
  /// the next clip" (QA Round 43).
  Future<void> _transportGate = Future<void>.value();

  /// Incremented on every transport enqueue. A superseded body (e.g. skip
  /// whose playFile finishes after the user tapped pause) must not leave
  /// audio playing when the user asked to pause.
  int _transportEpoch = 0;

  /// Snapshot captured before an optimistic skip title flip. Restored when
  /// pause preempts an in-flight skip so the user does not see "pause changed
  /// the clip".
  PlaybackSnapshot? _optimisticSkipSnapshot;

  /// Index chosen by [_primeOptimisticSkip]. The skip body plays THIS index
  /// instead of advancing again (double-advance made 2-clip queues wrap to
  /// the same track and feel like pause/seek-0).
  int? _optimisticSkipIndex;

  /// Sized for playFile's 8s setAudioSource cap plus native MethodChannel
  /// skip / pause round-trips.
  static const _transportBodyTimeout = Duration(seconds: 12);

  /// QA Aug 22 Issue 3: collapse rapid play/skip taps into one intentional
  /// command. 400ms sits in the recommended 300–500ms window.
  static const _controlDebounce = Duration(milliseconds: 400);

  DateTime? _lastSkipControlAt;
  DateTime? _lastPlayPauseControlAt;

  /// True while [_guardedSkip] is running (flush → prime → transport body →
  /// force-resume). A second next/prev must not prime again — on a 2-clip
  /// queue that double-prime wraps back to the same track (Issue 2).
  bool _skipInFlight = false;

  /// True when the newest transport op is pause/dismiss. Used so a
  /// superseded skip body does not pause the clip the user just skipped to.
  bool _latestTransportPausesPlayback = false;

  bool _transportCurrent(int epoch) => epoch == _transportEpoch;

  /// Accepts a next/prev tap only when no skip is in flight and the debounce
  /// window since the last accepted skip has elapsed. Discarded taps must
  /// not call [_primeOptimisticSkip] (that advances the queue pointer).
  bool _acceptSkipControl() {
    if (_skipInFlight) return false;
    final now = DateTime.now();
    final last = _lastSkipControlAt;
    if (last != null && now.difference(last) < _controlDebounce) {
      return false;
    }
    _lastSkipControlAt = now;
    return true;
  }

  /// Debounces play/pause so a double-tap cannot toggle twice into an
  /// undefined state. Pause is never blocked by [_skipInFlight] so the user
  /// can still stop audio during a slow skip.
  bool _acceptPlayPauseControl() {
    final now = DateTime.now();
    final last = _lastPlayPauseControlAt;
    if (last != null && now.difference(last) < _controlDebounce) {
      return false;
    }
    _lastPlayPauseControlAt = now;
    return true;
  }

  /// Stops an in-flight skip / playFile without tearing down the media session.
  ///
  /// [revertOptimisticSkip] distinguishes hard abort (pause/dismiss) from soft
  /// abort (skip/play preempting a prior load):
  /// - Hard: pause native (cancels deferred prepare via skipGeneration) and
  ///   stop ExoPlayer load.
  /// - Soft: invalidate Dart playFile generation only — never stop() and never
  ///   pauseNative. Soft stop made every next/prev pause audio and reset the
  ///   scrubber to 0; pauseNative raced skipNative and cancelled prepares.
  Future<void> _abortInFlightTransport(
      {required bool revertOptimisticSkip}) async {
    if (revertOptimisticSkip && _optimisticSkipSnapshot != null) {
      _emit(_optimisticSkipSnapshot!.copyWith(isPlaying: false));
      _optimisticSkipSnapshot = null;
      _optimisticSkipIndex = null;
    }
    final nativeActive = _nativeOwnsPlayback ||
        NativeAlarmsBridge.instance.lastSnapshot.isNativeActive;
    if (nativeActive) {
      if (revertOptimisticSkip) {
        try {
          await NativeAlarmsBridge.instance.pauseNative();
        } catch (_) {}
      }
      return;
    }
    if (revertOptimisticSkip) {
      try {
        await _audio.cancelInFlightPlay();
      } catch (_) {}
    } else {
      try {
        _audio.invalidateInFlightPlay();
      } catch (_) {}
    }
  }

  Future<T> _serializeTransport<T>(
    Future<T> Function(int epoch) body, {
    bool preempt = false,
    bool revertOptimisticSkip = false,
    bool pausesPlayback = false,
  }) {
    final epoch = ++_transportEpoch;
    _latestTransportPausesPlayback = pausesPlayback;
    final Future<void> previous;
    if (preempt) {
      final abort = _abortInFlightTransport(
        revertOptimisticSkip: revertOptimisticSkip,
      );
      // Soft abort is synchronous (generation bump only) — never wait on it.
      // Hard abort (pause) cuts the line immediately while cancel runs parallel.
      unawaited(abort);
      previous = Future<void>.value();
    } else {
      previous = _transportGate;
    }
    final completer = Completer<T>();
    _transportGate = previous
        .then((_) => null, onError: (Object _, StackTrace __) => null)
        .then((_) async {
      try {
        final result = await body(epoch).timeout(
          _transportBodyTimeout,
          onTimeout: () {
            throw TimeoutException(
              'transport: body exceeded $_transportBodyTimeout',
              _transportBodyTimeout,
            );
          },
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'PlaybackCoordinator._serializeTransport body failed: $e\n$st');
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      } finally {
        if (_transportCurrent(epoch)) {
          _optimisticSkipSnapshot = null;
        }
      }
    });
    return completer.future;
  }

  /// Schedule notification refresh off the transport hot path so next/prev /
  /// pause never wait on alarm-table rebuilds.
  void _refreshScheduleNotificationsDeferred() {
    unawaited(() async {
      try {
        await refreshScheduleNotifications?.call();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'PlaybackCoordinator: deferred schedule notif refresh failed: $e\n$st');
        }
      }
    }());
  }

  /// True while next/prev / clip play is swapping sources. Transient
  /// ExoPlayer `playing:false` after stop() must not flip the mini-player
  /// to paused or hide the bar (QA Round 48).
  ///
  /// Round 49: do NOT clear this when the skip Future completes — a late
  /// `ready`+`playing:false` after clear caused alternate pause/play on
  /// successive next/prev taps. Cleared only when we observe playing:true
  /// or the user explicitly pauses.
  bool _suppressTransientNotPlaying = false;

  /// If a newer transport op superseded [epoch] after audio already started,
  /// honor the user's latest intent — but ONLY when that intent is pause /
  /// dismiss. Skip→skip must not pause the newer clip (Round 47).
  Future<void> _honorSupersededTransport(int epoch) async {
    if (_transportCurrent(epoch)) return;
    if (!_latestTransportPausesPlayback) return;
    _suppressTransientNotPlaying = false;
    _userInitiatedPause = true;
    _emit(_snapshot.copyWith(isPlaying: false));
    if (_nativeOwnsPlayback ||
        NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
      try {
        await NativeAlarmsBridge.instance.pauseNative();
      } catch (_) {}
    } else {
      try {
        await _audio.pause();
      } catch (_) {}
    }
  }

  /// Called after a scheduled whisper finishes so notifications show the next slot.
  ///
  /// Round 24 — accepts a `forceAlarmRebuild` flag. When true, the
  /// underlying `syncWhisperNotifications` is instructed to bypass the
  /// native alarm bridge's structural fingerprint and fully cancel +
  /// re-register the alarm table. Use for user-initiated CRUD paths
  /// (Active toggle, schedule save/delete) where we can't be sure the
  /// fingerprint has actually shifted; leave false for the internal
  /// notification-tick refresh where the fingerprint short-circuit is
  /// what keeps the alarm chain stable.
  Future<void> Function({bool forceAlarmRebuild})? refreshScheduleNotifications;

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
    _audio.onPlayRequested = () => unawaited(_handleNotificationPlay());
    _audio.onPauseRequested = () => unawaited(_handleNotificationPause());
    _audio.onSkipToNextRequested = () => skipNext();
    _audio.onSkipToPreviousRequested = () => skipPrevious();
    _audio.onClipSessionChanged = () {
      unawaited(refreshScheduleNotifications?.call());
    };
    // Soft-fail: if `playFile` returns successfully but the native player
    // sits in `idle` / `loading` for >5s without ever reaching a playable
    // state, the handler fires this callback. Surface a snackbar ONLY —
    // never call stop(). stop() emitted activeIdle and hid the Spotify
    // mini-player while the notification card (and often the audio) kept
    // running; tapping notification play brought the bar back (QA Round 52).
    _audio.onPlaybackStartFailure = (title) {
      if (_userInitiatedPause) return;
      if (_suppressTransientNotPlaying) return;
      // Still audibly healthy — ignore a stale watchdog.
      if (_audio.isPlayingClip && _audio.isPlaying) return;
      if (_nativeOwnsPlayback) return;
      if (_errorController.isClosed) return;
      _errorController.add(PlaybackErrorEvent(
        PlaybackErrorReason.decodeFailed,
        clipTitle: title,
      ));
      // Keep the session (manualPlaying + titles) so the bar stays up;
      // only clear the playing flag so the icon matches reality.
      if (_snapshot.state == AppPlaybackState.manualPlaying ||
          _snapshot.state == AppPlaybackState.scheduledPlaying) {
        if (_snapshot.isPlaying) {
          _emit(_snapshot.copyWith(isPlaying: false));
        }
      }
    };
    _emit(
      PlaybackSnapshot(
        state: active ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
        modalVisible: false,
      ),
    );
    _playerSub = _audio.playerStateStream.listen(
      _onPlayerState,
      onError: (Object e, StackTrace st) {
        // Round 17: an uncaught error in the player state stream was the
        // root cause of "rapid pause/play crashes the app". Silently
        // swallow so the activity stays alive.
        if (kDebugMode) {
          debugPrint(
              'coordinator playerStateStream error (swallowed): $e\n$st');
        }
      },
    );
    // Round 22 — listen for native scheduled-playback transitions so the
    // mini-player lights up when an alarm-fired clip starts, flips the
    // play/pause icon when the user uses the notification shade, and
    // disappears when playback ends.
    _nativePlaybackSub = NativeAlarmsBridge.instance.stateStream.listen(
      _onNativePlaybackState,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint(
              'coordinator native state stream error (swallowed): $e\n$st');
        }
      },
    );
    // Round 29: poll native BEFORE starting silence keep-alive. Cold-start
    // used to call enterForeground first, which briefly grabbed focus and
    // paused the in-flight MediaPlayer — then the mini-player never lit
    // because scheduledPlaying was overwritten by activeIdle.
    NativePlaybackSnapshot? native;
    try {
      native = await NativeAlarmsBridge.instance.fetchPlaybackState();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('initialize: fetchPlaybackState failed: $e\n$st');
      }
    }
    if (native != null && native.isNativeActive) {
      _nativeScheduledActive = true;
      _nativeActiveScheduleId = native.scheduleId;
      try {
        await _audio.suspendSilenceForExternalPlayback();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('initialize: suspendSilence failed: $e\n$st');
        }
      }
      _emit(PlaybackSnapshot(
        state: AppPlaybackState.scheduledPlaying,
        isPlaying: native.isPlaying,
        playlistName: native.playlistName ?? 'WhisperBack',
        clipTitle: native.clipTitle ?? 'Scheduled whisper',
        durationMs: native.durationMs,
        modalVisible: false,
      ));
    } else if (active) {
      // Round 33 (Android): NEVER start ExoPlayer silence for scheduling —
      // native AlarmManager + WhisperKeepAliveService keep the process
      // alive. ExoPlayer silence was racing MediaPlayer and causing
      // intermittent auto-pause / missed fires on Samsung / Xiaomi / Vivo.
      await KeepAliveService.start();
      if (!Platform.isAndroid) {
        await _audio.enterForeground();
      } else {
        try {
          await _audio.suspendSilenceForExternalPlayback();
        } catch (_) {}
      }
    }
    startModeMonitoring();
  }

  /// Round 31 — public entry so UI / providers can force the coordinator
  /// to mirror native prefs even when the method-channel listener was
  /// null (app cold-started after AlarmManager already started audio).
  void applyNativePlaybackSnapshot(NativePlaybackSnapshot native) {
    _onNativePlaybackState(native);
  }

  /// Native FG MediaPlayer owns the session (playing or paused).
  bool get _nativeOwnsPlayback =>
      _nativeScheduledActive ||
      NativeAlarmsBridge.instance.lastSnapshot.isNativeActive;

  /// Schedule id native is currently playing. Cached so the idle
  /// transition can stamp the completion into the right store bucket
  /// even when the idle callback arrives with `scheduleId=null` (which
  /// happens after `stopSelfSafely` clears the fields between the state
  /// write and the notification broadcast).
  String? _nativeActiveScheduleId;

  /// Mirrors a native-playback transition into the UI snapshot so the
  /// mini-player and modal reflect what the OS-level service is actually
  /// playing. We use the existing `scheduledPlaying` state so all the
  /// downstream consumers (mini-player visibility, modal show button,
  /// snapshot tests) treat this as a "real" scheduled play even though
  /// the audio bytes are flowing through Kotlin instead of just_audio.
  ///
  /// Round 23 addition — this is ALSO the single choke point where a
  /// native fire gets mirrored into `ScheduleLastFiredStore` so the
  /// Dart engine's `_runTick` will NOT re-fire the same slot from
  /// `just_audio`. Without this, the user's QA "the first schedule
  /// works good but later ones are delayed / stopped working" was:
  ///   1. Native alarm fires slot 10:00, plays via MediaPlayer.
  ///   2. Dart engine ticks at 10:00, sees `lastFired.slot(id) = null`
  ///      (nothing stamped it), fires the SAME slot via just_audio.
  ///   3. Two audio streams contend for focus — MediaPlayer usually
  ///      wins the ducking race but the just_audio path can also mark
  ///      the whole coordinator as "playing scheduled" which changes
  ///      the visible UI mid-play and re-triggers snapshot refresh.
  ///   4. Because the snapshot was rebuilt mid-play, later alarms
  ///      registered in the same rebuild get cancelled + re-registered
  ///      with drifted times — which the user perceives as "the second
  ///      schedule was late" and eventually the tail dries up.
  ///
  /// The fix here has three parts. On `state=playing` we stamp the slot
  /// start immediately; on `state=idle` (natural completion / stop) we
  /// stamp the real completion time AND trigger a snapshot refresh so
  /// the tail always has ~half a day of fires queued.
  void _onNativePlaybackState(NativePlaybackSnapshot native) {
    try {
      if (native.isPlaying) {
        // Round 27: progress ticks (every 500 ms) also arrive as
        // `isPlaying` snapshots so the mini-player can scrub. Only the
        // FIRST transition into native play should stamp lastFired /
        // suspend silence / emit the scheduledPlaying frame.
        //
        // Round 41: if the user just tapped pause, ignore PLAYING ticks
        // until native reports paused (or they tap resume). The progress
        // ticker kept broadcasting PLAYING for up to ~500ms after the
        // optimistic pause, and `wasPaused` treated that as "resume" —
        // flipping the button back to pause and making the tap look dead.
        if (_userInitiatedPause) {
          return;
        }
        final titleChanged = native.clipTitle != null &&
            native.clipTitle!.isNotEmpty &&
            native.clipTitle != _snapshot.clipTitle;
        if (titleChanged) {
          // Native skip already started the new clip — release Dart skip latch
          // so a real user pause still works (playerState is ignored while
          // native owns audio, so latch would never clear otherwise).
          _suppressTransientNotPlaying = false;
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.scheduledPlaying,
            isPlaying: true,
            clipTitle: native.clipTitle,
            playlistName:
                native.playlistName ?? _snapshot.playlistName ?? 'WhisperBack',
            durationMs: native.durationMs > 0
                ? native.durationMs
                : _snapshot.durationMs,
            playlistId: native.playlistId ?? _snapshot.playlistId,
          ));
          unawaited(_ensurePlaylistCache(
              native.playlistId ?? _snapshot.playlistId));
          return;
        }
        final firstStart = !_nativeScheduledActive;
        final wasPaused = _nativeScheduledActive && !_snapshot.isPlaying;
        _nativeScheduledActive = true;
        if (firstStart) {
          final startedAt = DateTime.now();
          _nativeActiveScheduleId = native.scheduleId;
          _stampNativeFireStart(native.scheduleId, startedAt);
          unawaited(_ensurePlaylistCache(
              native.playlistId ?? _snapshot.playlistId));
          unawaited(() async {
            try {
              await _audio.suspendSilenceForExternalPlayback();
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint('suspendSilence on native play failed: $e\n$st');
              }
            }
          }());
        }
        if (firstStart || wasPaused) {
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.scheduledPlaying,
            isPlaying: true,
            playlistId: native.playlistId ?? _snapshot.playlistId,
            playlistName:
                native.playlistName ?? _snapshot.playlistName ?? 'WhisperBack',
            clipTitle:
                native.clipTitle ?? _snapshot.clipTitle ?? 'Scheduled whisper',
            durationMs: native.durationMs > 0
                ? native.durationMs
                : _snapshot.durationMs,
          ));
        } else if (native.durationMs > 0 &&
            native.durationMs != _snapshot.durationMs) {
          // Progress-only tick: keep duration fresh so the mini-player
          // scrubber does not stick at 0:00 after prepare.
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.scheduledPlaying,
            isPlaying: true,
            durationMs: native.durationMs,
            playlistId: native.playlistId ?? _snapshot.playlistId,
            playlistName:
                native.playlistName ?? _snapshot.playlistName ?? 'WhisperBack',
            clipTitle:
                native.clipTitle ?? _snapshot.clipTitle ?? 'Scheduled whisper',
          ));
        }
        return;
      }
      if (native.isPaused) {
        _nativeScheduledActive = true;
        if (_snapshot.isPlaying ||
            _snapshot.state != AppPlaybackState.scheduledPlaying) {
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.scheduledPlaying,
            isPlaying: false,
            playlistName:
                native.playlistName ?? _snapshot.playlistName ?? 'WhisperBack',
            clipTitle:
                native.clipTitle ?? _snapshot.clipTitle ?? 'Scheduled whisper',
            durationMs: native.durationMs > 0
                ? native.durationMs
                : _snapshot.durationMs,
          ));
        }
        return;
      }
      // Idle — clear the snapshot only if we'd previously promoted it.
      if (_nativeScheduledActive) {
        _nativeScheduledActive = false;
        // Round 24 — stamp actual completion so the "upcoming events"
        // widget and the always-on notification card show the correct
        // next-fire time. We do NOT trigger a full snapshot refresh
        // here: that path calls `applySnapshot`, which the Round-24
        // rewrite guards behind a STRUCTURAL fingerprint so it's now
        // a no-op unless the user actually changed a schedule. The
        // alarm table already contains the next 288 fires per
        // schedule, all pre-registered with `setAlarmClock`; the OS
        // will deliver them independently of anything the app does
        // after this point.
        final endedAt = DateTime.now();
        final scheduleId = _nativeActiveScheduleId ?? native.scheduleId;
        _nativeActiveScheduleId = null;
        // Round 33: on Android never restore ExoPlayer silence after a
        // native clip — KeepAliveService is enough and silence caused
        // the next schedule to auto-pause.
        if (!Platform.isAndroid) {
          unawaited(() async {
            try {
              await _audio.resumeSilenceAfterExternalPlayback();
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint('resumeSilence after native idle failed: $e\n$st');
              }
            }
          }());
        }
        // Don't blow away the snapshot if the Dart side has since started
        // its own clip (e.g. user tapped Play); we only roll back our own
        // scheduledPlaying frame.
        //
        // Round 47: MediaPlayer often goes briefly idle between skip
        // prepares. Demoting to activeIdle hid the mini-player while the
        // next clip was still audible. Keep scheduledPlaying (just mark
        // not playing) unless Dart has no clip and no skip is in flight.
        if (_snapshot.state == AppPlaybackState.scheduledPlaying) {
          final dartOwnsClip = _audio.currentPath != null ||
              _audio.isPlayingClip ||
              _audio.mediaItem != null;
          final skipInFlight =
              _optimisticSkipIndex != null || _suppressTransientNotPlaying;
          if (dartOwnsClip || skipInFlight) {
            // Keep session state so the mini-player never vanishes mid-skip.
            _emit(_snapshot.copyWith(isPlaying: _suppressTransientNotPlaying
                ? true
                : false));
          } else {
            // True end of native clip — clear metadata so the bar can hide.
            _emit(const PlaybackSnapshot(
              state: AppPlaybackState.activeIdle,
              isPlaying: false,
              modalVisible: false,
            ));
          }
        }
        // Round 35: stamp completion and AWAIT it before realigning
        // AlarmManager. `applySnapshot`'s STAGE 3 projection reads this
        // exact value straight out of `ScheduleLastFiredStore` (a
        // synchronous, in-memory-cached read). Previously the stamp write
        // and the Round-34 "realign" rebuild below were two INDEPENDENT
        // `unawaited()` tasks kicked off back-to-back with no ordering
        // between them — whichever task reached its critical line first
        // (a race that depends on device I/O speed / DB contention) won.
        // When the rebuild won, it projected the next alarm table from
        // the STALE (one-cycle-old) completion stamp instead of the one
        // that had just landed, arming the wrong epoch. That is what
        // produced the QA symptoms: scheduled whispers sometimes not
        // firing at all, and the gap between fires drifting
        // inconsistently instead of by a fixed, predictable amount.
        // Chaining these two steps sequentially in one task makes the
        // ordering deterministic.
        unawaited(() async {
          try {
            await _stampNativeFireCompletion(scheduleId, endedAt);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint(
                  'coordinator _stampNativeFireCompletion failed: $e\n$st');
            }
          }
          try {
            await _advanceShuffleCursorAfterFire(scheduleId);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('coordinator shuffle cursor advance failed: $e\n$st');
            }
          }
          try {
            await refreshScheduleNotifications?.call(forceAlarmRebuild: true);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint(
                  'coordinator realign after native fire failed: $e\n$st');
            }
          }
        }());
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('coordinator _onNativePlaybackState failed: $e\n$st');
      }
    }
  }

  void _stampNativeFireStart(String? scheduleId, DateTime when) {
    if (scheduleId == null || scheduleId.isEmpty) return;
    // Fire-and-forget; the store's `ensureLoaded` guarantees the pref
    // instance is cached before any first call in production. Wrapped
    // in a microtask so an early callback fired before the store has
    // been initialised (unit tests, cold-start race) doesn't throw
    // through the state listener.
    unawaited(() async {
      try {
        final store = await ScheduleLastFiredStore.ensureLoaded();
        // Round 24 — stamp ONLY the slot here. The completion stamp is
        // set by `_stampNativeFireCompletion` when the MediaPlayer
        // actually finishes. Setting completion == slot here would
        // collapse the projection's "case 1" (real end known) into
        // "case 2" (placeholder end = slot + duration), causing the
        // upcoming-events widget and the `applySnapshot` projection
        // to double-add the playlist duration.
        await store.setSlot(scheduleId, when);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('coordinator _stampNativeFireStart failed: $e\n$st');
        }
      }
    }());
  }

  /// Awaitable so callers can guarantee this write has landed in
  /// `ScheduleLastFiredStore` BEFORE reading it back (e.g. the Round 34
  /// alarm-table realign). Errors are the caller's responsibility to
  /// catch — see the single call site in `_onNativePlaybackState`.
  Future<void> _stampNativeFireCompletion(
      String? scheduleId, DateTime when) async {
    if (scheduleId == null || scheduleId.isEmpty) return;
    final store = await ScheduleLastFiredStore.ensureLoaded();
    await store.setCompletion(scheduleId, when);
  }

  /// Shuffle-on schedules play one clip per interval. Advance the
  /// rotation cursor AFTER the completion stamp so the following
  /// alarm realign assigns the next clip, not the one that just played.
  Future<void> _advanceShuffleCursorAfterFire(String? scheduleId) async {
    if (scheduleId == null || scheduleId.isEmpty) return;
    final repo = _schedules;
    if (repo == null) return;
    PlaybackSchedule? schedule;
    for (final s in await repo.getAll()) {
      if (s.id == scheduleId) {
        schedule = s;
        break;
      }
    }
    if (schedule == null || !schedule.shuffleEnabled) return;
    final store = await ScheduleLastFiredStore.ensureLoaded();
    await store.incrementShuffleCursor(scheduleId);
  }

  /// Lock-screen / audio_service notification already invoked
  /// [WhisperAudioHandler.pause]. Preempt any in-flight skip and sync
  /// coordinator + native state without double-pausing ExoPlayer.
  Future<void> _handleNotificationPause() {
    // Round 50: ignore MediaSession pause echoes triggered by ExoPlayer
    // stop() during next/prev source swap.
    if (_suppressTransientNotPlaying) {
      if (kDebugMode) {
        debugPrint('notification pause: ignored during skip latch');
      }
      return Future<void>.value();
    }
    // Round 51: in-app pause already flipped the snapshot. A second
    // entry (legacy echo) must not preempt transport / revert skip titles.
    if (_userInitiatedPause && !_snapshot.isPlaying) {
      return Future<void>.value();
    }
    return _serializeTransport(
      (epoch) async {
        if (!_transportCurrent(epoch)) return;
        if (_suppressTransientNotPlaying) return;
        if (_snapshot.state != AppPlaybackState.inactive &&
            !_systemDrivenPauseInFlight) {
          _userInitiatedPause = true;
        }
        if (_snapshot.isPlaying) {
          _emit(_snapshot.copyWith(isPlaying: false));
        }
        if (_nativeOwnsPlayback ||
            NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
          try {
            await NativeAlarmsBridge.instance.pauseNative();
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('notification pause: native failed: $e\n$st');
            }
          }
        }
      },
      preempt: true,
      revertOptimisticSkip: true,
      pausesPlayback: true,
    );
  }

  /// Lock-screen play after [WhisperAudioHandler.play] already resumed
  /// ExoPlayer — sync coordinator + native and cancel stale skips.
  Future<void> _handleNotificationPlay() {
    // Round 51: in-app resume / playFile already owns the snapshot.
    if (!_userInitiatedPause && _snapshot.isPlaying) {
      return Future<void>.value();
    }
    return _serializeTransport(
      (epoch) async {
        if (!_transportCurrent(epoch)) return;
        if (_snapshot.state != AppPlaybackState.inactive) {
          _userInitiatedPause = false;
        }
        if (!_snapshot.isPlaying) {
          _emit(_snapshot.copyWith(isPlaying: true));
        }
        if (_nativeOwnsPlayback ||
            NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
          try {
            await NativeAlarmsBridge.instance.resumeNative();
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('notification play: native failed: $e\n$st');
            }
          }
        }
      },
      preempt: true,
      revertOptimisticSkip: true,
    );
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

  /// Synchronous next/prev target for instant mini-player feedback.
  ({String title, int durationMs, int index})? _resolveSkipTarget(bool next) {
    final playlistId = _snapshot.playlistId;
    if (playlistId == null) {
      if (_libraryQueue.length <= 1) return null;
      final currentIndex = _libraryIndex < 0 ? 0 : _libraryIndex;
      final nextIndex = next
          ? (currentIndex + 1) % _libraryQueue.length
          : (currentIndex - 1 + _libraryQueue.length) % _libraryQueue.length;
      final clip = _libraryQueue[nextIndex];
      return (title: clip.title, durationMs: clip.durationMs, index: nextIndex);
    }
    if (_playlistClipCache.length <= 1) return null;
    final currentIndex = _playlistClipIndex ?? 0;
    final size = _playlistClipCache.length;
    final nextIndex =
        next ? (currentIndex + 1) % size : (currentIndex - 1 + size) % size;
    final clip = _playlistClipCache[nextIndex];
    return (title: clip.title, durationMs: clip.durationMs, index: nextIndex);
  }

  /// Flip title / play icon on the same frame as the tap — before transport
  /// serialization or native I/O.
  void _primeOptimisticSkip(bool next) {
    _userInitiatedPause = false;
    _playbackGeneration++;
    _optimisticSkipSnapshot = _snapshot;
    _optimisticSkipIndex = null;

    final native = _nativeOwnsPlayback ||
        NativeAlarmsBridge.instance.lastSnapshot.isNativeActive;
    if (native) {
      final target = _resolveSkipTarget(next);
      _optimisticSkipIndex = target?.index;
      _emit(_snapshot.copyWith(
        state: AppPlaybackState.scheduledPlaying,
        isPlaying: true,
        clipTitle: target?.title ?? _snapshot.clipTitle,
        durationMs: target?.durationMs ?? _snapshot.durationMs,
        modalVisible: false,
      ));
      return;
    }

    final target = _resolveSkipTarget(next);
    if (target == null) {
      if (_snapshot.playlistId == null && _libraryQueue.length == 1) {
        _emit(_snapshot.copyWith(isPlaying: true));
      }
      return;
    }

    _optimisticSkipIndex = target.index;
    final fromSchedule = _snapshot.state == AppPlaybackState.scheduledPlaying;
    if (_snapshot.playlistId == null) {
      _libraryIndex = target.index;
      _emit(_snapshot.copyWith(
        state: AppPlaybackState.manualPlaying,
        clipTitle: target.title,
        playlistName: target.title,
        isPlaying: true,
        durationMs: target.durationMs,
        modalVisible: false,
      ));
      _warmLibraryNeighbors();
    } else {
      _playlistClipIndex = target.index;
      _emit(_snapshot.copyWith(
        state: fromSchedule
            ? AppPlaybackState.scheduledPlaying
            : AppPlaybackState.manualPlaying,
        clipTitle: target.title,
        isPlaying: true,
        durationMs: target.durationMs,
        modalVisible: false,
      ));
      _warmPlaylistNeighbors();
    }
  }

  void _warmLibraryNeighbors() {
    if (_libraryQueue.length <= 1) return;
    final idx = _libraryIndex < 0 ? 0 : _libraryIndex;
    final n = _libraryQueue.length;
    unawaited(_audio.warmFileCache(_libraryQueue[(idx + 1) % n].filePath));
    unawaited(_audio.warmFileCache(_libraryQueue[(idx - 1 + n) % n].filePath));
  }

  void _warmPlaylistNeighbors() {
    if (_playlistClipCache.length <= 1) return;
    final idx = _playlistClipIndex ?? 0;
    final n = _playlistClipCache.length;
    unawaited(_audio.warmFileCache(_playlistClipCache[(idx + 1) % n].filePath));
    unawaited(
        _audio.warmFileCache(_playlistClipCache[(idx - 1 + n) % n].filePath));
  }

  /// Load playlist clips so optimistic next/prev can resolve titles while
  /// native MediaPlayer owns playback (cache is otherwise empty).
  Future<void> _ensurePlaylistCache(String? playlistId) async {
    if (playlistId == null || playlistId.isEmpty) return;
    if (_playlistClipCache.isNotEmpty) return;
    try {
      final clips = await _playlists.getClips(playlistId);
      if (clips.isNotEmpty && _playlistClipCache.isEmpty) {
        _playlistClipCache = clips;
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ensurePlaylistCache failed: $e\n$st');
      }
    }
  }

  /// Wraps `_skipPlaylistClip` in the unified transport gate AND
  /// a try/catch + error event so a thrown PlatformException from the
  /// native player never propagates out of a skip tap. The user perceives
  /// an unhandled throw as "app crashed when I pressed next" — which is
  /// the exact symptom they reported on the mini-player and modal
  /// controls.
  Future<void> _guardedSkip({required bool next}) async {
    // Issue 2 + 3 (Aug 22): discard rapid / overlapping next-prev before any
    // index mutation. Priming outside the gate used to advance twice on a
    // double-tap and wrap a 2-clip queue back onto the same track.
    if (!_acceptSkipControl()) return;
    _skipInFlight = true;
    try {
      // Invalidate in-flight completion BEFORE flushing so stop() cannot
      // auto-advance the playlist (that looked like a skip to the wrong clip).
      _playbackGeneration++;
      // Flush the current stream BEFORE the title flips so next/prev cannot
      // leave the old clip audible under the new metadata (BUG-001).
      if (!_nativeOwnsPlayback &&
          !NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
        try {
          await _audio.flushCurrentSource();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('skip: flush current source failed: $e\n$st');
          }
        }
      }
      _primeOptimisticSkip(next);
      // Latch until we explicitly finish the skip as playing. MediaSession
      // pause echoes from stop() must not win over next/prev.
      _suppressTransientNotPlaying = true;
      _userInitiatedPause = false;
      try {
        await _serializeTransport(
          (epoch) => _skipPlaylistClip(epoch, next: next),
          preempt: true,
        );
        // Spotify contract: skip always leaves the new clip PLAYING.
        if (_latestTransportPausesPlayback) return;
        _userInitiatedPause = false;
        if (_snapshot.state == AppPlaybackState.manualPlaying ||
            _snapshot.state == AppPlaybackState.scheduledPlaying ||
            _snapshot.clipTitle != null) {
          try {
            if (!_nativeOwnsPlayback &&
                !NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
              await _audio.resume();
            }
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('skip: force-resume failed: $e\n$st');
            }
          }
          _emit(_snapshot.copyWith(
            state: _snapshot.state == AppPlaybackState.scheduledPlaying ||
                    _nativeOwnsPlayback
                ? AppPlaybackState.scheduledPlaying
                : AppPlaybackState.manualPlaying,
            isPlaying: true,
            modalVisible: false,
          ));
          // Native skips never hit Dart playerState — clear latch here.
          // Dart skips keep the latch until playing:true (MediaSession echo).
          if (_nativeOwnsPlayback ||
              NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
            _suppressTransientNotPlaying = false;
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('skip${next ? 'Next' : 'Previous'} failed: $e\n$st');
        }
        // Keep the Spotify bar up even when a swap times out — audio /
        // MediaSession often still owns the previous or new clip.
        if (_snapshot.state != AppPlaybackState.manualPlaying &&
            _snapshot.state != AppPlaybackState.scheduledPlaying &&
            (_snapshot.clipTitle != null || _audio.currentPath != null)) {
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.manualPlaying,
            modalVisible: false,
          ));
        }
        // Don't spam "Playback failed" when the session is still healthy.
        final stillLive = _audio.isPlayingClip ||
            _audio.isPlaying ||
            _nativeOwnsPlayback ||
            NativeAlarmsBridge.instance.lastSnapshot.isNativeActive;
        if (!stillLive && !_errorController.isClosed) {
          _errorController.add(PlaybackErrorEvent(
            PlaybackErrorReason.decodeFailed,
            clipTitle: _snapshot.clipTitle,
          ));
        }
      }
    } finally {
      _skipInFlight = false;
    }
  }

  Future<void> _skipPlaylistClip(int epoch, {required bool next}) async {
    if (!_transportCurrent(epoch)) return;
    // Explicit skip is an unambiguous user intent to move forward/back, even
    // if they had previously tapped pause. Clear the sentinel so the next
    // natural completion in the new clip behaves normally.
    _userInitiatedPause = false;
    // Scheduled Android playback is owned by native MediaPlayer. Dart
    // skip used to call just_audio, which is idle in that state — the
    // mini-player and notification next/prev looked dead.
    if (_nativeOwnsPlayback ||
        NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
      _optimisticSkipIndex = null;
      try {
        await NativeAlarmsBridge.instance.skipNative(next: next);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('skip: native skip failed: $e\n$st');
        }
      }
      await _honorSupersededTransport(epoch);
      return;
    }
    // Invalidate any in-flight completion from the clip we're leaving.
    _playbackGeneration++;

    final playlistId = _snapshot.playlistId;
    if (playlistId == null) {
      // Library-queue context: walk through the currently shown clip list.
      if (_libraryQueue.length <= 1) {
        // Single clip — restart from the top so the button still feels alive
        // instead of silently doing nothing.
        if (_libraryQueue.isEmpty) return;
        _optimisticSkipIndex = null;
        await _audio.seek(Duration.zero);
        await _audio.resume();
        return;
      }
      // Prefer the index primed on the tap frame. Only re-compute when prime
      // could not resolve (empty queue at tap time) — never advance twice.
      final primed = _optimisticSkipIndex;
      _optimisticSkipIndex = null;
      final nextIndex = primed ??
          (next
              ? ((_libraryIndex < 0 ? 0 : _libraryIndex) + 1) %
                  _libraryQueue.length
              : ((_libraryIndex < 0 ? 0 : _libraryIndex) -
                      1 +
                      _libraryQueue.length) %
                  _libraryQueue.length);
      _libraryIndex = nextIndex;
      final clip = _libraryQueue[nextIndex];
      await _playClipInternal(
        clip,
        queue: _libraryQueue,
        transportEpoch: epoch,
        skipSnapshotEmit: true,
      );
      await _honorSupersededTransport(epoch);
      return;
    }

    var clips = _playlistClipCache;
    if (clips.isEmpty) {
      clips = await _playlists.getClips(playlistId);
      _playlistClipCache = clips;
    }
    if (clips.isEmpty) return;
    if (clips.length <= 1) {
      // Single-clip playlist: replay from the top instead of stopping —
      // matches user expectation for a "next" tap on a one-track playlist.
      _playlistClipIndex = 0;
      _optimisticSkipIndex = null;
      await _playClipAtIndex(
        playlistId,
        clips,
        0,
        fromSchedule: _snapshot.state == AppPlaybackState.scheduledPlaying,
        transportEpoch: epoch,
      );
      await _honorSupersededTransport(epoch);
      return;
    }

    // Prefer snapshot flags — avoid a SQLite getById on every next/prev tap.
    final shuffle = _snapshot.shuffleEnabled;
    final fromSchedule = _snapshot.state == AppPlaybackState.scheduledPlaying;

    if (shuffle) {
      _optimisticSkipIndex = null;
      // Lightweight shuffle skip: pick next via ShuffleEngine + sourceSwap.
      // Full `_playPlaylistInternal` re-hit DB, sleep/prayer checks, and
      // awaited notification refresh — that was multi-second next/prev lag.
      final clip = _nextShuffledClip(playlistId, clips);
      final idx = clips.indexWhere((c) => c.id == clip.id);
      if (idx >= 0) _playlistClipIndex = idx;
      try {
        await _audio.playFile(
          clip.filePath,
          title: clip.title,
          playlistName: _snapshot.playlistName,
          subtitle: fromSchedule
              ? RuntimeCopy.l10n.scheduledWhisper
              : RuntimeCopy.l10n.nowPlaying,
          playlistMode: true,
          sourceSwap: true,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('skip shuffle playFile failed: $e\n$st');
        }
        await _honorSupersededTransport(epoch);
        return;
      }
      _warmPlaylistNeighbors();
      if (_transportCurrent(epoch)) {
        _emit(_snapshot.copyWith(
          state: fromSchedule
              ? AppPlaybackState.scheduledPlaying
              : AppPlaybackState.manualPlaying,
          clipTitle: clip.title,
          isPlaying: true,
          durationMs: clip.durationMs,
          modalVisible: false,
        ));
      }
      _refreshScheduleNotificationsDeferred();
      await _honorSupersededTransport(epoch);
      return;
    }

    // Prefer primed index; only advance here when prime had no cache yet.
    final primed = _optimisticSkipIndex;
    _optimisticSkipIndex = null;
    final nextIndex = primed ??
        (next
            ? ((_playlistClipIndex ?? 0) + 1) % clips.length
            : ((_playlistClipIndex ?? 0) - 1 + clips.length) % clips.length);
    _playlistClipIndex = nextIndex;
    // Walk forward/back from the target so a missing file never leaves the
    // mini-player stranded mid-skip (which looked like "next hid the bar").
    final played = await _advanceToNextPlayable(
      playlistId,
      clips,
      nextIndex,
      fromSchedule: fromSchedule,
      transportEpoch: epoch,
    );
    if (played == null && clips.isNotEmpty) {
      // Absolute fallback: restart the first playable clip so next never
      // feels like a stop.
      await _advanceToNextPlayable(
        playlistId,
        clips,
        0,
        fromSchedule: fromSchedule,
        transportEpoch: epoch,
      );
    }
    await _honorSupersededTransport(epoch);
  }

  Future<void> _playClipAtIndex(
    String playlistId,
    List<AudioClip> clips,
    int index, {
    required bool fromSchedule,
    int? transportEpoch,
  }) async {
    if (index < 0 || index >= clips.length) return;
    if (transportEpoch != null && !_transportCurrent(transportEpoch)) return;

    final clip = clips[index];
    if (!_isPlayablePath(clip.filePath)) return;

    // Hot path: reuse snapshot metadata instead of SQLite getById.
    var playlistName = _snapshot.playlistName;
    var shuffleEnabled = _snapshot.shuffleEnabled;
    if (playlistName == null || playlistName.isEmpty) {
      final playlist = await _playlists.getById(playlistId);
      playlistName = playlist?.name;
      shuffleEnabled = playlist?.shuffleEnabled ?? false;
    }
    if (transportEpoch != null && !_transportCurrent(transportEpoch)) return;
    _playbackGeneration++;

    final swapping = _snapshot.state == AppPlaybackState.manualPlaying ||
        _snapshot.state == AppPlaybackState.scheduledPlaying;
    try {
      await _audio.playFile(
        clip.filePath,
        title: clip.title,
        playlistName: playlistName,
        subtitle: fromSchedule
            ? RuntimeCopy.l10n.scheduledWhisper
            : RuntimeCopy.l10n.nowPlaying,
        playlistMode: clips.length > 1,
        sourceSwap: swapping,
      );
    } catch (_) {
      return;
    }

    if (transportEpoch != null && !_transportCurrent(transportEpoch)) {
      return;
    }

    _playlistClipIndex = index;
    _warmPlaylistNeighbors();
    _emit(
      _snapshot.copyWith(
        state: fromSchedule
            ? AppPlaybackState.scheduledPlaying
            : AppPlaybackState.manualPlaying,
        playlistId: playlistId,
        playlistName: playlistName,
        clipTitle: clip.title,
        isPlaying: true,
        shuffleEnabled: shuffleEnabled,
        modalVisible: false,
        durationMs: clip.durationMs,
      ),
    );
    _refreshScheduleNotificationsDeferred();
  }

  Future<void> _deactivateFromNotification() async {
    await _appState.setActive(false);
    // Round 32: Stop the native MediaPlayer too — otherwise the ongoing
    // card "Stop" left scheduled audio playing with no UI (QA: cannot pause).
    if (_nativeOwnsPlayback) {
      try {
        await NativeAlarmsBridge.instance.stopNative();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('deactivateFromNotification: stopNative failed: $e\n$st');
        }
      }
      _nativeScheduledActive = false;
    }
    await _audio.exitForeground();
    await AdhanPlayer.instance.stop();
    _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
  }

  void _onPlayerState(PlayerState state) {
    // Round 32: while native MediaPlayer owns scheduled audio, ignore
    // just_audio silence keep-alive events — they were flipping
    // isPlaying=false and made the mini-player look auto-paused.
    if (_nativeOwnsPlayback) return;

    if (_snapshot.state == AppPlaybackState.manualPlaying ||
        _snapshot.state == AppPlaybackState.scheduledPlaying) {
      final playing = state.playing;

      // Explicit user pause: confirm paused into the snapshot; never
      // re-light isPlaying from a late playing:true (pre-pause race).
      if (_userInitiatedPause) {
        if (!playing && _snapshot.isPlaying) {
          _emit(_snapshot.copyWith(isPlaying: false));
        }
        return;
      }

      // Skip / source-swap latch: ignore transient playing:false from
      // stop(); clear latch and sync true when the new clip is audible.
      if (_suppressTransientNotPlaying) {
        if (playing) {
          _suppressTransientNotPlaying = false;
          if (!_snapshot.isPlaying) {
            _emit(_snapshot.copyWith(isPlaying: true));
          }
        }
        return;
      }

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
    // Capture generation BEFORE yielding so a concurrent skip/next that
    // bumps `_playbackGeneration` can invalidate this completion.
    final generationAtStart = _playbackGeneration;

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

    if (generationAtStart != _playbackGeneration) {
      // A skip / new play superseded this completion — do nothing.
      return;
    }

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
      // Shuffle-on: one clip per interval (round-robin). Do not walk
      // the rest of the playlist — that is what made interval timing
      // occupy the full playlist length.
      final shuffleThisFire =
          _activeScheduleShuffle ?? _snapshot.shuffleEnabled;
      if (!shuffleThisFire) {
        // Shuffle-off: play EVERY clip in the playlist for this fire,
        // then finish.
        final playlistId = _snapshot.playlistId;
        if (playlistId != null) {
          final clips = await _playlists.getClips(playlistId);
          if (clips.isNotEmpty) {
            final lastIndex = _playlistClipIndex ?? 0;
            final nextIndex = lastIndex + 1;
            if (nextIndex < clips.length) {
              final played = await _advanceToNextPlayable(
                playlistId,
                clips,
                nextIndex,
                fromSchedule: true,
              );
              if (played != null) return;
            }
          }
        }
      }
      await _finishScheduledClip();
      return;
    }

    if (_snapshot.playlistId == null) {
      // Multi-clip library queue: advance like a playlist instead of
      // stopping after every track (which made next/prev + auto-end feel
      // random when the user expected continuous playback).
      if (_libraryQueue.length > 1) {
        final currentIndex = _libraryIndex < 0 ? 0 : _libraryIndex;
        final nextIndex = (currentIndex + 1) % _libraryQueue.length;
        _libraryIndex = nextIndex;
        final clip = _libraryQueue[nextIndex];
        if (generationAtStart != _playbackGeneration) return;
        await playClip(clip, queue: _libraryQueue);
        return;
      }
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

    // Sequential playlist: advance to the NEXT clip, wrapping to the first
    // after the last so "next" / natural end never hides the mini-player.
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
    int? transportEpoch,
  }) async {
    var playlistName = _snapshot.playlistName;
    var shuffleEnabled = _snapshot.shuffleEnabled;
    if (playlistName == null || playlistName.isEmpty) {
      final playlist = await _playlists.getById(playlistId);
      playlistName = playlist?.name;
      shuffleEnabled = playlist?.shuffleEnabled ?? false;
    }
    final swapping = _snapshot.state == AppPlaybackState.manualPlaying ||
        _snapshot.state == AppPlaybackState.scheduledPlaying;
    final visited = <int>{};
    var index = startIndex;
    while (visited.add(index)) {
      if (transportEpoch != null && !_transportCurrent(transportEpoch)) {
        return null;
      }
      if (index < 0 || index >= clips.length) break;
      final clip = clips[index];
      if (_isPlayablePath(clip.filePath)) {
        try {
          _playbackGeneration++;
          await _audio.playFile(
            clip.filePath,
            title: clip.title,
            playlistName: playlistName,
            subtitle: fromSchedule
                ? RuntimeCopy.l10n.scheduledWhisper
                : RuntimeCopy.l10n.nowPlaying,
            playlistMode: clips.length > 1,
            sourceSwap: swapping,
          );
          if (transportEpoch != null && !_transportCurrent(transportEpoch)) {
            return null;
          }
          _playlistClipIndex = index;
          _warmPlaylistNeighbors();
          _emit(
            _snapshot.copyWith(
              state: fromSchedule
                  ? AppPlaybackState.scheduledPlaying
                  : AppPlaybackState.manualPlaying,
              playlistId: playlistId,
              playlistName: playlistName,
              clipTitle: clip.title,
              isPlaying: true,
              shuffleEnabled: shuffleEnabled,
              modalVisible: false,
              durationMs: clip.durationMs,
            ),
          );
          _refreshScheduleNotificationsDeferred();
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
      try {
        await _advanceShuffleCursorAfterFire(completedScheduleId);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('finishScheduledClip: shuffle cursor failed: $e\n$st');
        }
      }
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
    // Round 33: Android schedules are native-only. Restarting ExoPlayer
    // silence here was the #1 intermittent auto-pause root cause.
    if (Platform.isAndroid) {
      await KeepAliveService.start();
      try {
        await NativeAlarmsBridge.instance.fetchPlaybackState();
      } catch (_) {}
      if (_nativeOwnsPlayback) {
        try {
          await _audio.suspendSilenceForExternalPlayback();
        } catch (_) {}
      }
      return;
    }
    if (_nativeOwnsPlayback) return;
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
    return _serializeTransport((epoch) async {
      // Belt-and-suspenders disable check at the very last moment before
      // we touch audio_service. Between the engine reading the schedule
      // and this body running inside the play-gate, the user may have
      // toggled the schedule OFF (or the app-wide Active toggle OFF) —
      // honor that even though the engine already passed its own check.
      // We deliberately use the cheaper `getForPlaylist` (single-row
      // query) instead of `getAll` so this extra check inside the play
      // gate stays sub-millisecond and never throttles legitimate fires.
      if (!await _appState.isActive()) return false;
      final sleep = await _sleep.getActive();
      if (_sleep.isSleepActive(sleep)) {
        return false;
      }
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
      // Round 18: tear down the native keep-alive FG service so the OS
      // reclaims the wake lock and the user no longer sees the
      // "WhisperBack is active" status bar icon.
      await KeepAliveService.stop();
    } else {
      _emit(_snapshot.copyWith(
        state: AppPlaybackState.activeIdle,
        isPlaying: false,
      ));
      await _appState.setActive(true);
      // Round 18: start the native keep-alive FG service FIRST so the
      // OS recognises the process as user-visible BEFORE any of the
      // audio_service work runs. This is what survives swipe-away on
      // Samsung One UI 6 / Vivo Funtouch 14 / Xiaomi MIUI 14 — the
      // partial wake lock + high-priority ongoing notification puts
      // the process in the "user-visible foreground service" bucket
      // that OEM battery managers respect even without a battery
      // exemption grant.
      await KeepAliveService.start();
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
      // Round 24 — Active toggle changes the alarm-table state (from
      // "cancelled" to "populated") so we MUST bypass the structural
      // fingerprint here. Otherwise on Vivo / Xiaomi the toggle from
      // OFF → ON on a previously-persisted schedule set could hit a
      // cached fingerprint that matches an ALREADY-CANCELLED table
      // and skip re-registration entirely.
      await refreshScheduleNotifications?.call(forceAlarmRebuild: true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '_activateInBackground: initial notif refresh failed: $e\n$st');
      }
    }
    // Round 33: on Android do NOT start ExoPlayer silence — KeepAlive
    // native FG + AlarmManager are enough. Silence was fighting scheduled
    // MediaPlayer and causing intermittent auto-pause.
    if (!Platform.isAndroid) {
      try {
        await _audio.enterForeground();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('_activateInBackground: enterForeground failed: $e\n$st');
        }
      }
    } else {
      try {
        await _audio.suspendSilenceForExternalPlayback();
      } catch (_) {}
    }
    try {
      await refreshModeState();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('_activateInBackground: refreshModeState failed: $e\n$st');
      }
    }
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
    return _serializeTransport(
      (_) => _playPlaylistInternal(playlistId, fromSchedule: fromSchedule),
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
    if (fromSchedule) {
      final sleep = await _sleep.getActive();
      if (_sleep.isSleepActive(sleep)) return false;
    }

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
    _playlistClipCache = clips;

    final playlist = await _playlists.getById(playlistId);
    // The schedule's own shuffle flag wins for scheduled fires (so toggling
    // shuffle in the schedule builder actually takes effect), then the
    // playlist's own setting is used as the fallback. Previously the
    // schedule-side shuffle flag was effectively ignored.
    final shuffle = (fromSchedule && _activeScheduleShuffle != null)
        ? _activeScheduleShuffle!
        : (playlist?.shuffleEnabled ?? false);
    AudioClip clip;
    if (fromSchedule && shuffle) {
      // Scheduled shuffle is round-robin: one clip per interval, in
      // playlist order, wrapping after the last clip. Random
      // ShuffleEngine is only for manual playlist play.
      final store = await ScheduleLastFiredStore.ensureLoaded();
      final cursor = _activeScheduleId == null
          ? 0
          : store.shuffleCursor(_activeScheduleId!);
      final index = clips.isEmpty ? 0 : cursor % clips.length;
      clip = clips[index];
      _playlistClipIndex = index;
    } else if (shuffle) {
      clip = _nextShuffledClip(playlistId, clips);
      _playlistClipIndex = null;
    } else {
      clip = clips.first;
      _playlistClipIndex = 0;
    }
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
      _playbackGeneration++;
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
        durationMs: clip.durationMs,
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
    return _serializeTransport(
      (epoch) => _playClipInternal(clip, queue: queue, transportEpoch: epoch),
      preempt: true,
    );
  }

  Future<void> _playClipInternal(
    AudioClip clip, {
    List<AudioClip>? queue,
    int? transportEpoch,
    bool skipSnapshotEmit = false,
  }) async {
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

    // Do NOT call `_audio.stop()` before swapping clips. stop() routes to
    // stopClip(), which restarts the silence keep-alive on Active=ON and
    // races the incoming playFile — the root cause of library next/prev
    // hanging then surfacing "Couldn't play …" (playFile handles ExoPlayer
    // source swap via `_player.stop()` only).

    _libraryQueue =
        (queue == null || queue.isEmpty) ? <AudioClip>[clip] : queue;
    _libraryIndex = _libraryQueue.indexWhere((c) => c.id == clip.id);
    if (_libraryIndex < 0) _libraryIndex = 0;
    _playlistClipCache = const [];
    _userInitiatedPause = false;

    if (!skipSnapshotEmit) {
      // Optimistic: show the now-playing sheet instantly for snappy feedback.
      _playbackGeneration++;
      _emit(PlaybackSnapshot(
        state: AppPlaybackState.manualPlaying,
        playlistName: clip.title,
        clipTitle: clip.title,
        isPlaying: true,
        modalVisible: false,
        durationMs: clip.durationMs,
      ));
    }

    if (transportEpoch != null && !_transportCurrent(transportEpoch)) {
      return;
    }

    try {
      await _audio.playFile(
        clip.filePath,
        title: clip.title,
        subtitle: RuntimeCopy.l10n.libraryPreview,
        playlistMode: _libraryQueue.length > 1,
        sourceSwap: skipSnapshotEmit,
      );
    } catch (e, st) {
      if (!_transportCurrent(transportEpoch ?? _transportEpoch)) {
        return;
      }
      if (kDebugMode) {
        debugPrint('playClip: playFile failed: $e\n$st');
      }
      // Skip swaps must NOT call stop() — that emits activeIdle and hides
      // the Spotify mini-player while the user is still tapping next/prev.
      if (skipSnapshotEmit) {
        if (!_errorController.isClosed) {
          _errorController.add(PlaybackErrorEvent(
            PlaybackErrorReason.decodeFailed,
            clipTitle: clip.title,
          ));
        }
        return;
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
    // crash the play tap. Keep it off the transport gate so skip/pause stay
    // responsive.
    _refreshScheduleNotificationsDeferred();
    if (transportEpoch != null) {
      await _honorSupersededTransport(transportEpoch);
    }
    _warmLibraryNeighbors();
    if (skipSnapshotEmit &&
        (transportEpoch == null || _transportCurrent(transportEpoch))) {
      // Confirm title/duration after the swap so the mini-player cannot
      // keep painting the previous clip metadata.
      _emit(_snapshot.copyWith(
        state: AppPlaybackState.manualPlaying,
        playlistName: clip.title,
        clipTitle: clip.title,
        isPlaying: true,
        durationMs: clip.durationMs,
        modalVisible: false,
      ));
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

  Future<void> pause() {
    if (!_acceptPlayPauseControl()) return Future<void>.value();
    _suppressTransientNotPlaying = false;
    if (_snapshot.isPlaying) {
      _userInitiatedPause = true;
      _emit(_snapshot.copyWith(isPlaying: false));
    }
    return _serializeTransport((epoch) async {
      if (!_transportCurrent(epoch)) return;
      _userInitiatedPause = true;
      // Round 22 — when a scheduled clip is being played by the native
      // FG service (not just_audio), `_audio.pause()` is a no-op. Route
      // the pause request through the native bridge so the actual
      // audio actually stops.
      if (_nativeOwnsPlayback ||
          NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
        _nativeScheduledActive = true;
        try {
          await NativeAlarmsBridge.instance.pauseNative();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('pause: native pause failed: $e\n$st');
          }
        }
        return;
      }
      try {
        await _audio.pause();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'pause: _audio.pause failed (UI already updated): $e\n$st');
        }
      }
    }, preempt: true, revertOptimisticSkip: true, pausesPlayback: true);
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
    // Round 18: HARDENED against the actual root causes the user
    // reported: "cross icon crashes the app" and "after cross, no
    // background processing happens".
    //
    // The old `hideClipMediaNotification` call published `playing:
    // false, processingState: idle, controls: []` — which told
    // audio_service "we're done", which called `Service.
    // stopForeground()`, which let the OS reap our process within
    // seconds. The user perceived this as "after cross, schedules
    // stop and notification disappears".
    //
    // New contract (matches the user's mental model):
    //   1. Pause the player so audio stops immediately.
    //   2. Hide the UI (mini-player + modal).
    //   3. DO NOT touch the audio_service media session OR drop
    //      the FG service binding. If Active is ON, the silence
    //      keep-alive is invoked synchronously so the FG service
    //      transitions cleanly from clip → silence without ever
    //      releasing the foreground state.
    //   4. If Active is OFF, fully stop (since the user has no
    //      expectation of background work in that mode).
    //
    // Everything is gated through `_serializeTransport` so skip / pause /
    // resume never run in parallel on different native engines.
    return _serializeTransport((epoch) async {
      if (!_transportCurrent(epoch)) return;
      bool wasActive = false;
      try {
        wasActive = await _appState.isActive();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('dismissPlayer: isActive lookup failed: $e\n$st');
        }
      }

      // UI: instantly clear the mini-player + modal so the user sees
      // their tap take effect even if the native calls below are slow.
      _emit(PlaybackSnapshot(
        state:
            wasActive ? AppPlaybackState.activeIdle : AppPlaybackState.inactive,
        isPlaying: false,
        modalVisible: false,
      ));

      _userInitiatedPause = true;

      // Round 22 — if the native scheduled-playback service is the
      // active source, stop IT first. Otherwise the audio keeps going
      // while the mini-player UI claims it stopped, which was one of
      // the user's reported symptoms ("it does not stop even though I
      // open the app and click the pause/resume in notification bar").
      if (_nativeOwnsPlayback) {
        _nativeScheduledActive = false;
        try {
          await NativeAlarmsBridge.instance.stopNative();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('dismissPlayer: native stop failed: $e\n$st');
          }
        }
        try {
          await refreshScheduleNotifications?.call();
        } catch (_) {}
        return;
      }

      if (wasActive) {
        // Active mode: hand off to silence keep-alive. We stop the
        // clip player (so audio actually ceases) BUT we do not drop
        // the FG service. `stop()` resolves to handler.stopClip() which
        // already handles the keep-alive transition when _keepAlive
        // is true (Round 18 made the transition atomic — no idle
        // publish in between).
        try {
          await _audio.stop();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('dismissPlayer: stop failed (Active): $e\n$st');
          }
        }
      } else {
        // Inactive mode: pause keeps the position so the user can
        // resume by re-tapping the clip. We don't need the FG
        // service since the user explicitly turned off background
        // work via the Active toggle.
        try {
          await _audio.pause();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('dismissPlayer: pause failed (Inactive): $e\n$st');
          }
        }
      }

      try {
        await refreshScheduleNotifications?.call();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('dismissPlayer: notif refresh failed: $e\n$st');
        }
      }
    }, preempt: true, revertOptimisticSkip: true, pausesPlayback: true);
  }

  Future<void> resume() {
    if (!_acceptPlayPauseControl()) return Future<void>.value();
    if (!_snapshot.isPlaying && _snapshot.state != AppPlaybackState.inactive) {
      _userInitiatedPause = false;
      _emit(_snapshot.copyWith(isPlaying: true));
    }
    return _serializeTransport((epoch) async {
      if (!_transportCurrent(epoch)) return;
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
      if (!_snapshot.isPlaying) {
        _emit(_snapshot.copyWith(isPlaying: true));
      }

      // Round 22 — when the visible scheduledPlaying snapshot is owned by
      // the native FG service, the resume tap must go back to native so
      // the MediaPlayer actually resumes. just_audio's resume would be a
      // no-op (nothing was queued in it).
      if (_nativeOwnsPlayback ||
          NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
        _nativeScheduledActive = true;
        try {
          await NativeAlarmsBridge.instance.resumeNative();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('resume: native resume failed: $e\n$st');
          }
          _emit(previous);
        }
        return;
      }

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

        // Fast path: already in a play session (paused mid-clip). Resume
        // ExoPlayer without re-running sleep/prayer GPS lookups — that was
        // multi-hundred-ms lag on every pause→play tap.
        if (_snapshot.state == AppPlaybackState.manualPlaying ||
            _snapshot.state == AppPlaybackState.scheduledPlaying) {
          await _audio.resume();
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
    }, preempt: true, revertOptimisticSkip: true);
  }

  Future<void> stop() async {
    _playlistClipIndex = null;
    _playlistClipCache = const [];
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

    // Round 22 — if native scheduled playback is the active source,
    // tear it down too. Otherwise the alarm-clock FG service keeps
    // emitting audio after stop().
    if (_nativeOwnsPlayback) {
      _nativeScheduledActive = false;
      try {
        await NativeAlarmsBridge.instance.stopNative();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('stop: native stop failed: $e\n$st');
        }
      }
    }

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

    final prayer =
        kAdhanFeatureEnabled ? await _prayer.getCurrentPrayerWindow() : null;
    if (prayer != null) {
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.prayerPaused, isPlaying: false));
      return false;
    }

    return true;
  }

  Future<void> refreshModeState() async {
    final active = await _appState.isActive();

    if (kAdhanFeatureEnabled) {
      // Adhan voice is decoupled from the master Active toggle so users still
      // hear the call to prayer even when WhisperBack whispers are off.
      // Round 30: never start Adhan over an in-flight scheduled whisper —
      // AudioSession.setActive would steal focus and look like auto-pause.
      final nativeOwns = _nativeOwnsPlayback;
      if (!nativeOwns) {
        final prayer = await _prayer.getCurrentPrayerWindow();
        if (prayer != null && await _prayer.adhanEnabled()) {
          final key = '${prayer.name}-${prayer.start.toIso8601String()}';
          if (_lastAdhanWindowKey != key) {
            _lastAdhanWindowKey = key;
            unawaited(AdhanPlayer.instance.playFor(key));
          }
        }
      }
    }

    if (!active) {
      _emit(const PlaybackSnapshot(state: AppPlaybackState.inactive));
      return;
    }

    final nativeOwns = _nativeOwnsPlayback;

    final sleep = await _sleep.getActive();
    if (_sleep.isSleepActive(sleep)) {
      // BUG-002: Sleep Mode is a hard barrier. Stop native scheduled
      // audio AND pause Dart playback for the rest of the window.
      try {
        await NativeAlarmsBridge.instance.setSleepBarrier(
          endMs: sleep!.endTime.millisecondsSinceEpoch,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('refreshModeState: setSleepBarrier failed: $e\n$st');
        }
      }
      if (nativeOwns) {
        try {
          await NativeAlarmsBridge.instance.stopNative();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('refreshModeState: stopNative for sleep failed: $e\n$st');
          }
        }
        _nativeScheduledActive = false;
      } else {
        await _systemPause();
      }
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.sleepPaused, isPlaying: false));
      return;
    }
    try {
      await NativeAlarmsBridge.instance.clearSleepBarrier();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('refreshModeState: clearSleepBarrier failed: $e\n$st');
      }
    }

    final prayer =
        kAdhanFeatureEnabled ? await _prayer.getCurrentPrayerWindow() : null;
    if (prayer != null) {
      if (nativeOwns) return;
      await _systemPause();
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.prayerPaused, isPlaying: false));
      return;
    }

    // Round 29: never overwrite an in-flight scheduled session with
    // activeIdle — the 15s mode timer was blanking the mini-player.
    if (nativeOwns) return;

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
    _nativePlaybackSub?.cancel();
    _snapshotController.close();
    _errorController.close();
  }
}
