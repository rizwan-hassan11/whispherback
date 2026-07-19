import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/feature_flags.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/sleep_repository.dart';
import '../../domain/entities/audio_clip.dart';
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
      final still = _snapshot.isPlaying && (_snapshot.clipTitle == title);
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
      // Round 18: ALSO restart the native keep-alive service. If the
      // process was killed and the user just relaunched the app from
      // the launcher, the native service is no longer running — we
      // need to bring it back so background scheduling works.
      await KeepAliveService.start();
      await _audio.enterForeground();
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
        final firstStart = !_nativeScheduledActive;
        final wasPaused = _nativeScheduledActive && !_snapshot.isPlaying;
        _nativeScheduledActive = true;
        if (firstStart) {
          final startedAt = DateTime.now();
          _nativeActiveScheduleId = native.scheduleId;
          _stampNativeFireStart(native.scheduleId, startedAt);
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
        _stampNativeFireCompletion(scheduleId, endedAt);
        // Round 27 — restore the silence keep-alive now that native
        // MediaPlayer has released the media stream.
        unawaited(() async {
          try {
            await _audio.resumeSilenceAfterExternalPlayback();
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('resumeSilence after native idle failed: $e\n$st');
            }
          }
        }());
        // Don't blow away the snapshot if the Dart side has since started
        // its own clip (e.g. user tapped Play); we only roll back our own
        // scheduledPlaying frame.
        if (_snapshot.state == AppPlaybackState.scheduledPlaying) {
          _emit(_snapshot.copyWith(
            state: AppPlaybackState.activeIdle,
            isPlaying: false,
            modalVisible: false,
          ));
        }
        // Refresh only the LOCAL notification card so "next in 5 min"
        // updates. This is `flutter_local_notifications` land, NOT
        // AlarmManager; the tail-refill decision is now the sole
        // responsibility of `applySnapshot`'s periodic-refill window
        // (default 12 h) and the schedule editor CRUD path.
        unawaited(() async {
          try {
            await refreshScheduleNotifications?.call();
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint(
                  'coordinator refresh after native fire failed: $e\n$st');
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

  void _stampNativeFireCompletion(String? scheduleId, DateTime when) {
    if (scheduleId == null || scheduleId.isEmpty) return;
    unawaited(() async {
      try {
        final store = await ScheduleLastFiredStore.ensureLoaded();
        await store.setCompletion(scheduleId, when);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('coordinator _stampNativeFireCompletion failed: $e\n$st');
        }
      }
    }());
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
    // Invalidate any in-flight completion from the clip we're leaving.
    _playbackGeneration++;
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
    // Walk forward/back from the target so a missing file never leaves the
    // mini-player stranded mid-skip (which looked like "next hid the bar").
    final played = await _advanceToNextPlayable(
      playlistId,
      clips,
      nextIndex,
      fromSchedule: fromSchedule,
    );
    if (played == null && clips.isNotEmpty) {
      // Absolute fallback: restart the first playable clip so next never
      // feels like a stop.
      await _advanceToNextPlayable(
        playlistId,
        clips,
        0,
        fromSchedule: fromSchedule,
      );
    }
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
    _playbackGeneration++;

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
        durationMs: clip.durationMs,
      ),
    );
    await refreshScheduleNotifications?.call();
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
      // Round 28: play EVERY clip in the playlist for a scheduled fire,
      // then finish. Previously we called `_finishScheduledClip` after
      // the first clip — multi-clip schedules stopped after track 1.
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
  }) async {
    final playlist = await _playlists.getById(playlistId);
    final visited = <int>{};
    var index = startIndex;
    while (visited.add(index)) {
      if (index < 0 || index >= clips.length) break;
      final clip = clips[index];
      if (_isPlayablePath(clip.filePath)) {
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
              durationMs: clip.durationMs,
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
    // Round 30: always re-poll prefs before the heartbeat may restart
    // silence — lastSnapshot can lag Kotlin's KEY_NATIVE_ACTIVE write.
    try {
      await NativeAlarmsBridge.instance.fetchPlaybackState();
    } catch (_) {}
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
    try {
      await _audio.enterForeground();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('_activateInBackground: enterForeground failed: $e\n$st');
      }
    }
    try {
      await refreshModeState();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('_activateInBackground: refreshModeState failed: $e\n$st');
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
    _playbackGeneration++;
    _emit(PlaybackSnapshot(
      state: AppPlaybackState.manualPlaying,
      playlistName: clip.title,
      clipTitle: clip.title,
      isPlaying: true,
      modalVisible: false,
      durationMs: clip.durationMs,
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
      // Round 22 — when a scheduled clip is being played by the native
      // FG service (not just_audio), `_audio.pause()` is a no-op. Route
      // the pause request through the native bridge so the actual
      // audio actually stops.
      if (_nativeOwnsPlayback) {
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
    // Everything is gated through `_serializePauseResume` so the
    // user can mash pause / cross / play / pause as fast as they
    // like and only ONE native state change is ever in flight.
    return _serializePauseResume(() async {
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

      // Round 22 — when the visible scheduledPlaying snapshot is owned by
      // the native FG service, the resume tap must go back to native so
      // the MediaPlayer actually resumes. just_audio's resume would be a
      // no-op (nothing was queued in it).
      if (_nativeOwnsPlayback) {
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
      // Round 30: never auto-pause an in-flight scheduled clip for sleep.
      // Product contract — schedules only stop on completion or explicit
      // user pause. Sleep still pauses Dart-side manual playback.
      if (nativeOwns) return;
      await _systemPause();
      _emit(_snapshot.copyWith(
          state: AppPlaybackState.sleepPaused, isPlaying: false));
      return;
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
