import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../l10n/runtime_copy.dart';
import '../scheduler/native_alarms_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

WhisperAudioHandler? _whisperAudioHandler;

/// True when [AudioService.init] succeeded and the handler is bound to Android.
bool whisperAudioServiceBound = false;

WhisperAudioHandler get whisperAudioHandler =>
    _whisperAudioHandler ??= WhisperAudioHandler();

set whisperAudioHandler(WhisperAudioHandler handler) =>
    _whisperAudioHandler = handler;

/// Album art on the media notification + lock screen.
final Uri _albumArtUri = Uri.parse(
  'android.resource://com.whisperback.whisperback/drawable/ic_notification',
);

/// Production audio handler following the official audio_service + just_audio
/// pattern: one clip player drives the MediaSession; a silent idle player keeps
/// the process alive for scheduling without touching the media notification.
class WhisperAudioHandler extends BaseAudioHandler with SeekHandler {
  WhisperAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [MediaControl.play],
        systemActions: const {
          MediaAction.seek,
          MediaAction.stop,
          MediaAction.play,
          MediaAction.pause,
        },
        androidCompactActionIndices: const [0],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
    // Round 17: EVERY player stream MUST have an `onError` handler.
    // Without it, an uncaught PlatformException from the native player
    // (Samsung One UI "(-38) MediaPlayerNative", Vivo Funtouch
    // "MediaCodec error", Xiaomi MIUI focus revocation) propagates up
    // the stream subscription and crashes the audio_service plugin's
    // own listeners, which in turn force-closes the activity. The user
    // reported "rapid pause/resume crashes the app" — the actual
    // throw was happening in a stream callback that the per-tap
    // try/catch could never see. All three streams now swallow errors.
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('player.playbackEventStream error (swallowed): $e\n$st');
        }
      },
    );
    _player.durationStream.listen(
      _onDurationReady,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('player.durationStream error (swallowed): $e\n$st');
        }
      },
    );
    _player.positionStream.listen(
      (_) {
        if (_playingClip && _player.playing) {
          _publishClipControls(
            playing: true,
            processing: _player.processingState,
          );
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('player.positionStream error (swallowed): $e\n$st');
        }
      },
    );
    // Round 17: also subscribe to player state explicitly so we can
    // catch the FATAL state and reset _playingClip / restart silence
    // keep-alive without leaving the FG service in a half-dead state.
    _player.playerStateStream.listen(
      (state) {
        // Nothing to do here for normal transitions — `_broadcastState`
        // covers UI. This subscription exists purely for error catching.
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('player.playerStateStream error (swallowed): $e\n$st');
        }
      },
    );
  }

  /// Silent loop while Active + idle — drives the audio_service foreground service.
  ///
  /// `handleAudioSessionActivation: false` is CRITICAL. By default just_audio
  /// calls `AudioSession.setActive(true)` on EVERY `play()` — including the
  /// inaudible keep-alive silence loop. With the `.music()` config that
  /// requests permanent `AndroidAudioFocusGainType.gain`, which PAUSES every
  /// other app (YouTube, Spotify, podcasts…). Because the keep-alive loop
  /// restarts on the engine heartbeat, other apps got paused over and over
  /// and the user had to keep tapping resume. We now own focus activation
  /// ourselves: only real clip playback ([playFile] / [play]) grabs focus,
  /// and the silent keep-alive never does.
  final AudioPlayer _player = AudioPlayer(handleAudioSessionActivation: false);

  AudioPlayer get player => _player;

  bool _keepAlive = false;
  bool _standalonePlayback = false;
  bool _audioSessionReady = false;
  bool _playingClip = false;
  bool _playlistMode = false;

  /// True while native [WhisperPlaybackService] owns the audible clip.
  /// Prevents the silence keep-alive (and the engine's 5-second heartbeat
  /// that restarts it) from re-binding ExoPlayer mid-schedule and
  /// interrupting MediaPlayer — the QA "schedule pauses after a few
  /// seconds" root cause alongside transient audio focus.
  bool _silenceSuspendedForExternal = false;
  String? _silencePath;

  String? _clipTitle;

  void Function()? onStopRequested;
  void Function()? onStopClipRequested;
  void Function()? onPlayRequested;
  void Function()? onPauseRequested;
  Future<void> Function()? onSkipToNextRequested;
  Future<void> Function()? onSkipToPreviousRequested;
  void Function()? onClipSessionChanged;

  bool get isPlayingClip => _playingClip;
  bool get isKeepAliveActive => _keepAlive && !_playingClip;
  // True only when the audio_service media card is ACTUALLY live (silence
  // loop started + playing). The extra `_keepAliveRunning` guard guarantees
  // we never report "card is up" if `_startIdleKeepAlive` threw silently on
  // an OEM where `setAudioSource(silence)` is rejected.
  bool get isForegroundNotificationActive =>
      whisperAudioServiceBound &&
      isKeepAliveActive &&
      _keepAliveRunning &&
      _player.playing &&
      mediaItem.value != null;
  // Render the flutter persistent notification whenever:
  //   • no clip is playing (clip uses its own media notification), AND
  //   • the audio_service keep-alive card is NOT actually live.
  // The previous version mis-reported "card live" when keep-alive threw
  // silently, leaving the user with NO notification at all on the very
  // devices where the silence loop fails (Vivo, Infinix, some Xiaomi MIUI).
  // Now we render the flutter notification AS A FALLBACK in that case.
  bool get shouldUseFlutterActiveNotification =>
      !isPlayingClip && !isForegroundNotificationActive;
  bool get occupiesMediaNotification =>
      _playingClip ||
      (_keepAlive && mediaItem.value != null) ||
      _player.processingState != ProcessingState.idle;
  String? get currentClipTitle => _clipTitle;

  /// Pre-warms the audio session so the very first `playFile` doesn't race
  /// with native session activation. Without this, on Samsung / fresh installs
  /// the first recorded clip's `playFile` call completes BEFORE the OS has
  /// granted audio focus, so the underlying `MediaPlayer` plays silently and
  /// the user sees nothing happen. Called once from `main()` after
  /// `AudioService.init` so it never blocks app launch — best effort.
  Future<void> warmUp() async {
    try {
      await _ensureAudioSession();
    } catch (_) {
      // Already swallowed errors — `_ensureAudioSession` is best-effort and
      // will retry on the first `playFile` call anyway.
    }
  }

  Future<void> _ensureAudioSession() async {
    if (_audioSessionReady) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Phone calls, alarms, navigation prompts, and other apps with higher
    // audio focus need to interrupt us cleanly. Without this hook the clip
    // would keep playing under the call (or stay paused after the call ends
    // and the user has to manually tap Play). We pause on focus loss and
    // duck (volume reduce) on transient ducks; resume on focus restore only
    // if we were actually playing a clip when interrupted.
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (_playingClip) {
              unawaited(_player.setVolume(0.3));
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_playingClip && _player.playing) {
              _wasPlayingBeforeInterruption = true;
              unawaited(_player.pause());
            }
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (_playingClip) {
              unawaited(_player.setVolume(1));
            }
            break;
          case AudioInterruptionType.pause:
            if (_wasPlayingBeforeInterruption && _playingClip) {
              _wasPlayingBeforeInterruption = false;
              unawaited(_player.play());
            }
            break;
          case AudioInterruptionType.unknown:
            // OS told us interruption ended but the type was unknown; do
            // nothing here — the user can hit Play if they want to resume.
            break;
        }
      }
    });
    // Disconnected headphones (or BT) — pause clip so the user doesn't
    // accidentally blast the speaker.
    session.becomingNoisyEventStream.listen((_) {
      if (_playingClip && _player.playing) {
        _wasPlayingBeforeInterruption = false;
        unawaited(_player.pause());
      }
    });
    _audioSessionReady = true;
  }

  bool _wasPlayingBeforeInterruption = false;

  /// Releases audio focus so other apps (YouTube, Spotify, podcasts) resume
  /// after our clip finishes. Best-effort — a failure here is harmless, the
  /// OS reaps focus when the process ends anyway.
  Future<void> _releaseAudioFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('releaseAudioFocus failed (swallowed): $e\n$st');
      }
    }
  }

  // ── Active session (scheduling keep-alive, no media notification) ───────────

  Future<void> enterForeground() async {
    _keepAlive = true;
    if (_playingClip) return;
    // Round 27: native scheduled playback owns the media stream —
    // do NOT restart the silence loop underneath it.
    if (_silenceSuspendedForExternal) return;
    // Round 29: prefs / last bridge snapshot may say native is active
    // before Dart's suspendSilence flag flips (cold start race).
    if (NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
      _silenceSuspendedForExternal = true;
      return;
    }
    // Round 15: idempotent — skip the silence-loop rebuild when the
    // loop is ALREADY running. Without this guard, the engine's 5-
    // second heartbeat (Round 14) would re-run `setAudioSource(silence)`
    // every tick, which on Samsung One UI 6 throws transient
    // PlatformExceptions ("MediaSource currently in use") and on
    // Vivo Funtouch occasionally crashes the audio_service binding
    // outright. Only re-bind when we know the loop is dead.
    if (_keepAliveRunning && _player.playing) return;
    await _startIdleKeepAlive();
  }

  /// True after `_startIdleKeepAlive` actually committed and the silence
  /// loop is running. Exposed via `isKeepAliveRunning` so notification_sync
  /// can know whether to render the flutter persistent notification as a
  /// fallback (silence loop never started → no audio_service media card →
  /// the user has NO indication the app is active without our fallback).
  bool _keepAliveRunning = false;
  bool get isKeepAliveRunning => _keepAliveRunning;

  Future<void> _startIdleKeepAlive() async {
    if (_playingClip) return;
    if (_silenceSuspendedForExternal) return;
    if (NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
      _silenceSuspendedForExternal = true;
      return;
    }
    // Up to 3 attempts with a short backoff between each. The first
    // attempt sometimes lands BEFORE the system audio focus grant
    // completes on cold start (Samsung Exynos firmware in particular),
    // and `_player.setAudioSource` throws PlatformException("(-1004)
    // setDataSource failed"). A 250 ms retry succeeds reliably.
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ensureAudioSession();
        // NOTE: we deliberately do NOT call `session.setActive(true)` here.
        // The keep-alive loop is inaudible silence whose only job is to keep
        // the foreground service bound for scheduling. Requesting audio focus
        // would pause whatever the user is listening to in other apps
        // (YouTube, Spotify…) every time the loop (re)starts. Focus is only
        // grabbed for real clip playback in `playFile` / `play`.

        final path = await _ensureSilenceFile();
        final copy = RuntimeCopy.l10n;
        final item = MediaItem(
          id: path,
          title: copy.notificationActiveTitle,
          album: 'WhisperBack',
          artist: copy.notificationActiveBodyIdle,
          artUri: _albumArtUri,
          displayTitle: copy.notificationActiveTitle,
          displaySubtitle: copy.notificationActiveBodyIdle,
          extras: const {'mode': 'keep_alive'},
        );
        mediaItem.add(item);
        queue.add([item]);

        // Round 16: volume 0 was making some Samsung / Vivo / Xiaomi
        // OEM audio policy daemons revoke our audio focus ("you're
        // not really playing anything"). 0.001 is mathematically
        // inaudible (-60 dB; below the hardware noise floor) but
        // counts as real playback for the OEM focus check. Combined
        // with the longer 10-second silence file (also Round 16),
        // this keeps the FG service genuinely alive when the user
        // closes the app.
        await _player.setVolume(0.001);
        await _player.setLoopMode(LoopMode.one);
        await _player.setSpeed(1);
        await _player.setAudioSource(AudioSource.file(path), preload: true);

        playbackState.add(
          PlaybackState(
            controls: const [_stopControl],
            systemActions: const {MediaAction.stop},
            androidCompactActionIndices: const [0],
            processingState: AudioProcessingState.ready,
            playing: true,
            updatePosition: Duration.zero,
            bufferedPosition: Duration.zero,
            speed: 1.0,
          ),
        );

        await _player.play();
        _keepAliveRunning = true;
        return;
      } catch (e, st) {
        _keepAliveRunning = false;
        if (kDebugMode) {
          debugPrint('keep-alive attempt $attempt/3 failed: $e\n$st');
        }
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }
    // All retries exhausted. The Flutter ongoing notification posted by
    // `notification_sync` is now unconditional and takes over user-
    // visible status. Schedules still drive playback via the in-process
    // `Timer.periodic` as long as the engine is alive — which the
    // posted notification keeps active for long enough on most OEMs
    // for at least one fire to land.
    if (kDebugMode) {
      debugPrint('keep-alive: all retries exhausted — relying on '
          'flutter ongoing notification fallback.');
    }
  }

  Future<void> updateActiveSessionInfo() async {
    if (_playingClip) return;
    if (_silenceSuspendedForExternal) return;
    if (NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) {
      _silenceSuspendedForExternal = true;
      return;
    }
    if (_keepAlive && !_player.playing) {
      await _startIdleKeepAlive();
    }
  }

  /// Round 27 — pause the inaudible silence loop while native scheduled
  /// playback owns the media stream. Leaves `_keepAlive` / the FG
  /// binding intent intact so [resumeSilenceAfterExternalPlayback] can
  /// restore the loop when the native clip ends. Without this, the
  /// schedule engine's 5-second `ensureForeground` heartbeat restarts
  /// ExoPlayer mid-clip and the native MediaPlayer pauses.
  Future<void> suspendSilenceForExternalPlayback() async {
    _silenceSuspendedForExternal = true;
    if (_playingClip) return;
    try {
      if (_player.playing) {
        await _player.pause();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('suspendSilence: pause failed: $e\n$st');
      }
    }
    _keepAliveRunning = false;
  }

  /// Restores the silence keep-alive after native scheduled playback ends.
  Future<void> resumeSilenceAfterExternalPlayback() async {
    _silenceSuspendedForExternal = false;
    if (!_keepAlive || _playingClip) return;
    try {
      await _startIdleKeepAlive();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('resumeSilence: keep-alive restart failed: $e\n$st');
      }
    }
  }

  Future<void> exitForeground() async {
    _keepAlive = false;
    _keepAliveRunning = false;
    _playingClip = false;
    _standalonePlayback = false;
    _playlistMode = false;
    _silenceSuspendedForExternal = false;
    _clipTitle = null;
    // Each call is independently try/caught so the master Active
    // toggle's OFF path never throws a PlatformException out to the
    // UI callback. The user expects "tap toggle off" to ALWAYS
    // succeed visually — any failure here just leaves residual
    // session state that the OS reaps.
    try {
      await _player.stop();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('exitForeground: _player.stop failed: $e\n$st');
      }
    }
    await _releaseAudioFocus();
    try {
      mediaItem.add(null);
      queue.add([]);
    } catch (_) {}
    try {
      // Publish a fully-idle playback state BEFORE asking the service
      // to stop. Without this, audio_service sometimes leaves a
      // "WhisperBack — paused" notification stuck on the lock-screen
      // for several seconds after the toggle goes off.
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
    } catch (_) {}
    try {
      // Call super.stop() ONLY here, on the deliberate user-OFF action.
      // The standalone-clip stop path skips this to avoid OEM
      // activity-kill (see `stopClip` / `stop` notes above), but the
      // user explicitly chose to stop the foreground service here so
      // we tear it down cleanly. A PlatformException at this point
      // still cannot crash the app because of the surrounding try.
      await super.stop();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('exitForeground: super.stop failed: $e\n$st');
      }
    }
  }

  // ── Clip / playlist playback (Spotify-style media notification) ───────────

  Future<void> playFile(
    String path, {
    String title = 'WhisperBack',
    String? playlistName,
    String? subtitle,
    bool playlistMode = false,
  }) async {
    // Reject obviously bad inputs early so the caller's `try/catch` can show
    // a snackbar instead of the system silently doing nothing.
    if (path.isEmpty) {
      throw ArgumentError('playFile requires a non-empty path');
    }
    if (!File(path).existsSync()) {
      throw StateError('Clip file is missing on disk: $path');
    }

    await _ensureAudioSession();
    final session = await AudioSession.instance;
    await session.setActive(true);

    // Round 16: ALWAYS publish a playing-true PlaybackState BEFORE
    // setAudioSource. This forces audio_service's native side to
    // call `Service.startForeground()` IMMEDIATELY rather than
    // waiting for the first playerEvent → broadcastState round-trip,
    // which on Vivo / Xiaomi was sometimes 200-500ms late and let
    // the OS reap the service first (the QA report "audio cuts off
    // when I close the app while playing"). With this pre-flight
    // state push, the service is FG-bound before the activity can
    // get destroyed.
    try {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: true,
          controls: const [MediaControl.pause, _stopControl],
          systemActions: const {
            MediaAction.seek,
            MediaAction.play,
            MediaAction.pause,
            MediaAction.stop,
          },
          androidCompactActionIndices: const [0],
        ),
      );
    } catch (_) {
      // Best-effort. The next _player event will re-publish anyway.
    }

    // CRITICAL: if a previous source is still loading (rapid tap or schedule
    // racing with manual play), `setAudioSource` would queue behind it on
    // some OEMs and the new source never starts. Force-stop the player first
    // so the next `setAudioSource` is a clean swap.
    if (_player.processingState == ProcessingState.loading ||
        _player.processingState == ProcessingState.buffering) {
      try {
        await _player.stop();
      } catch (_) {
        // Best-effort: keep going; the explicit setAudioSource below will
        // overwrite the source even if stop() couldn't unwind cleanly.
      }
    }

    _playingClip = true;
    _clipTitle = title;
    _playlistMode = playlistMode;
    if (!_keepAlive) _standalonePlayback = true;

    final item = _clipMediaItem(
      path: path,
      title: title,
      playlistName: playlistName,
      subtitle: subtitle,
    );
    mediaItem.add(item);
    queue.add([item]);
    _publishClipControls(playing: false, processing: ProcessingState.loading);

    await _player.setVolume(1);
    await _player.setSpeed(1);
    await _player.setLoopMode(LoopMode.off);
    // CRITICAL: cap setAudioSource at 8 seconds. The just_audio future can
    // hang indefinitely if the underlying ExoPlayer / native MediaPlayer
    // gets into a stuck state (observed on Samsung One UI after rapid
    // record/import/play cycles). Without this cap the play-gate mutex in
    // PlaybackCoordinator stays held forever and every subsequent tap
    // queues behind a dead future — that is the QA report "after some
    // time clips/playlists delete but don't play".
    try {
      await _player
          .setAudioSource(AudioSource.file(path), preload: true)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // The player is wedged. Force-stop so the next playFile can rebuild
      // the source cleanly, and rethrow so the coordinator surfaces a
      // decodeFailed snackbar instead of silently swallowing the failure.
      try {
        await _player.stop();
      } catch (_) {}
      rethrow;
    }
    onClipSessionChanged?.call();
    await play();

    // Fire-and-forget watcher: if the native player never reaches a playable
    // state within 5s, emit `onPlaybackStartFailure` so the coordinator can
    // surface a snackbar. We deliberately do NOT block `playFile` on this —
    // the previous design awaited a 2s deadline INSIDE `playFile`, which on
    // slow Samsung devices threw spurious errors even for healthy clips,
    // caused the playback gate to hold for 2s on real failures (blocking the
    // next user tap), and locked the engine into failure backoff after the
    // first scheduled fire. Now the watcher is decoupled: playback is
    // launched immediately, and stuck-state detection happens out of band.
    _scheduleStartWatchdog();
  }

  /// Outstanding watchdog for "play() called but processing state never
  /// advanced". Cancelled and replaced on every new playFile so we never
  /// fire late for a clip the user has already moved on from.
  Timer? _startWatchdog;

  /// Optional callback the coordinator wires up to surface a snackbar when
  /// playback truly never started. We use a callback (not a stream) so the
  /// signal stays decoupled from `PlaybackErrorEvent` — the coordinator
  /// decides how to phrase the user-visible message.
  void Function(String? clipTitle)? onPlaybackStartFailure;

  void _scheduleStartWatchdog() {
    _startWatchdog?.cancel();
    final expectedTitle = _clipTitle;
    _startWatchdog = Timer(const Duration(seconds: 5), () {
      // If the player did reach `ready` / `buffering` / `completed` or is
      // actually playing, we're fine — no need to alarm the user. This
      // catches the genuinely stuck case (audio focus denied, decoder
      // crash, content URI revoked between picker and play).
      if (!_playingClip) return;
      final ps = _player.processingState;
      if (ps == ProcessingState.ready ||
          ps == ProcessingState.buffering ||
          ps == ProcessingState.completed) {
        return;
      }
      if (_player.playing) return;
      // Still in `idle` or `loading` after 5s — surface as a soft warning.
      onPlaybackStartFailure?.call(expectedTitle);
    });
  }

  MediaItem _clipMediaItem({
    required String path,
    required String title,
    String? playlistName,
    String? subtitle,
    Duration? duration,
  }) {
    final line = subtitle ?? RuntimeCopy.l10n.nowPlaying;
    return MediaItem(
      id: path,
      title: title,
      album: playlistName ?? 'WhisperBack',
      artist: line,
      duration: duration,
      artUri: _albumArtUri,
      displayTitle: title,
      displaySubtitle: playlistName ?? line,
      displayDescription: line,
      extras: const {'mode': 'clip'},
    );
  }

  void _onDurationReady(Duration? dur) {
    if (!_playingClip || dur == null) return;
    final current = mediaItem.value;
    if (current == null) return;
    if (current.duration == dur) return;
    mediaItem.add(_clipMediaItem(
      path: current.id,
      title: current.title,
      playlistName: current.album,
      subtitle: current.artist,
      duration: dur,
    ));
  }

  Future<void> stopClip() async {
    if (!_playingClip && _player.processingState == ProcessingState.idle) {
      return;
    }

    // Cancel any pending start-watchdog so we don't fire a stale "playback
    // start failed" snackbar for a clip the user explicitly stopped.
    _startWatchdog?.cancel();
    _startWatchdog = null;

    _playingClip = false;
    _clipTitle = null;
    _playlistMode = false;

    // EVERY native bridge call below is independently try/caught.
    // `_player.stop()`, `mediaItem.add(null)`, `queue.add([])`,
    // `playbackState.add(...)`, and `super.stop()` can EACH throw a
    // PlatformException on certain OEM firmwares (especially Samsung
    // One UI 6 / Vivo Funtouch 14) when the underlying media session
    // is in a half-torn-down state. The user reported "tapping the
    // cross icon crashed the app" even after we wrapped every UI
    // callback — the throw was happening DEEPER inside this method
    // and propagating up through `coordinator.stop` → the modal's
    // `_safeCall`, where the global zone handler still couldn't
    // prevent a UI lockup if the throw came inside a synchronous
    // event-bus emission. Now nothing here can ever escape.
    // Round 18: when keep-alive is enabled, transition straight from
    // the clip player to the silence loop WITHOUT publishing an idle
    // playbackState in between. The old order (stop player → publish
    // idle → start silence) gave audio_service a window (~50-200ms
    // on slow Samsung firmware) to call `Service.stopForeground()`
    // because it saw `playing: false`. The user's "after cross icon
    // no background processing happens" trace was this exact gap —
    // the silence loop didn't restart in time. Now we either go
    // clip → silence atomically (Active ON) or clip → fully idle
    // (Active OFF).
    if (_keepAlive) {
      // Stop the clip player but DO NOT publish playing:false. The
      // next playbackState publish (inside _startIdleKeepAlive) is
      // `playing: true` which keeps the FG service bound throughout.
      try {
        await _player.stop();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('stopClip: _player.stop failed (keep-alive): $e\n$st');
        }
      }
      try {
        onClipSessionChanged?.call();
      } catch (_) {}
      _standalonePlayback = false;
      // Release focus so whatever the user was listening to elsewhere
      // resumes; the silence loop we restart below never re-grabs it.
      await _releaseAudioFocus();
      try {
        await _startIdleKeepAlive();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('stopClip: keep-alive restart failed: $e\n$st');
        }
      }
      return;
    }

    try {
      await _player.stop();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('stopClip: _player.stop failed: $e\n$st');
      }
    }
    try {
      mediaItem.add(null);
      queue.add([]);
    } catch (_) {}

    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
        ),
      );
    } catch (_) {}

    try {
      onClipSessionChanged?.call();
    } catch (_) {}

    // Give focus back so other apps (YouTube/Spotify) resume.
    await _releaseAudioFocus();

    if (_standalonePlayback) {
      _standalonePlayback = false;
      // CRITICAL: do NOT call `super.stop()` here. `audio_service`'s
      // `super.stop()` calls `stopSelf()` on the underlying Android
      // foreground service. On Samsung One UI 6 / Vivo Funtouch 14
      // and several Xiaomi MIUI builds that tear-down can also
      // terminate the host Activity because the FG-service binding
      // was the only strong reference keeping it alive. The user's
      // exact QA report — "tapping the cross icon CLOSES the app
      // instead of pausing the clip" — was this teardown. Leaving
      // the media session bound is harmless: the next playFile()
      // will reuse it; otherwise the OS reaps it when the process
      // dies naturally. We've already published an empty
      // playbackState above so the lock-screen notification fades
      // away on its own.
      if (kDebugMode) {
        debugPrint(
            'stopClip: standalone teardown — keeping AudioService bound to '
            'avoid OEM activity-kill on super.stop()');
      }
    }
  }

  Future<String> _ensureSilenceFile() async {
    if (_silencePath != null && File(_silencePath!).existsSync()) {
      return _silencePath!;
    }
    final dir = await getApplicationSupportDirectory();
    // Round 16: bumped to v2 so devices that cached the 1-second
    // version from previous installs pick up the new 10-second one
    // (and don't keep using the rapid-loop version that some OEMs
    // misclassify as "not playing").
    final file = File(p.join(dir.path, 'whisperback_session_silence_v2.wav'));
    if (!file.existsSync()) {
      await file.writeAsBytes(_silentWav());
    }
    _silencePath = file.path;
    return file.path;
  }

  Uint8List _silentWav({int seconds = 10, int sampleRate = 44100}) {
    const channels = 2;
    final numSamples = seconds * sampleRate;
    final dataSize = numSamples * channels * 2;
    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }

    void u16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1);
    u16(channels);
    u32(sampleRate);
    u32(sampleRate * channels * 2);
    u16(channels * 2);
    u16(16);
    str('data');
    u32(dataSize);
    bytes.add(Uint8List(dataSize));
    return bytes.toBytes();
  }

  // ── audio_service callbacks (notification + lock screen buttons) ──────────

  @override
  Future<void> play() async {
    if (!_playingClip) return;

    // Round 15: each of these calls is independently try/caught so a
    // single failure (e.g. audio focus revoked because we're rapidly
    // toggling) cannot block the player.play() below or surface as
    // an uncaught exception that crashes the activity. See the
    // matching comment in `pause()` for the full failure mode.
    try {
      await _ensureAudioSession();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('handler.play: _ensureAudioSession failed: $e\n$st');
      }
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('handler.play: setActive failed: $e\n$st');
      }
    }

    if (_player.processingState == ProcessingState.completed) {
      try {
        await _player.seek(Duration.zero);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('handler.play: seek-to-zero failed: $e\n$st');
        }
      }
    }

    _publishClipControls(
      playing: true,
      processing: _player.processingState,
    );

    try {
      await _player.play();
      try {
        onPlayRequested?.call();
      } catch (_) {}
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('handler.play: _player.play failed (handled): $e\n$st');
      }
      _publishClipControls(
        playing: false,
        processing: _player.processingState,
      );
      // Round 15: do NOT rethrow. The coordinator's `resume()` already
      // optimistically flipped the UI to "playing"; if we throw here
      // the `_safeCall` wrapper swallows the error but the UI is now
      // stuck on "playing" while the player is actually paused. By
      // returning normally, the next `playerStateStream` event drives
      // the UI back to its true state.
    }
  }

  /// Round 15: hides the lock-screen media notification while keeping
  /// the audio_service session alive so the next `playFile` can re-
  /// attach without paying the FG-service rebind cost. Used by
  /// `dismissPlayer`.
  ///
  /// CRITICAL: we also reset `_playingClip = false` so the next call
  /// to `NotificationService.showActiveOngoing` actually shows the
  /// WhisperBack-active card (it early-returns when `_playingClip`
  /// is true). Without that reset, the user would see NEITHER the
  /// media card (we just hid it) NOR the WhisperBack-active card
  /// (the showActiveOngoing call short-circuits) — the QA report
  /// "after cross icon, no notification is shown at all" is exactly
  /// that gap.
  Future<void> hideClipMediaNotification() async {
    if (!_playingClip) return;
    _playingClip = false;
    try {
      mediaItem.add(null);
      queue.add([]);
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('hideClipMediaNotification failed (handled): $e\n$st');
      }
    }
  }

  @override
  Future<void> pause() async {
    if (!_playingClip) return;

    _publishClipControls(
      playing: false,
      processing: _player.processingState,
    );

    // Round 15 hardening: any failure from `_player.pause()` MUST be
    // swallowed locally. On Samsung One UI + just_audio, calling
    // `pause()` while a previous `play()` is still being awaited by
    // ExoPlayer's native thread throws a PlatformException("(-38)
    // MediaPlayerNative") that — if rethrown — surfaces through
    // audio_service's PlaybackEvent listener as an uncaught
    // PlatformChannel error and crashes the host activity. The user's
    // QA report "rapid pause/play crashes the app" is reliably
    // reproducible on Galaxy A series with this exact failure mode.
    // The optimistic UI flip above has already informed the coordinator;
    // the player will settle into its real state on the next
    // playerStateStream event regardless of whether THIS pause call
    // succeeded.
    try {
      await _player.pause();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('handler.pause: _player.pause failed (handled): $e\n$st');
      }
    }
    try {
      onPauseRequested?.call();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// `SeekHandler` mixin defaults `seekForward` / `seekBackward` to a 10-second
  /// jump. On a 2-5 second whisper clip that sails past the end, fires
  /// `ProcessingState.completed`, and the coordinator's auto-advance kicks
  /// in — the user perceives this as "tapping pause skipped to the next
  /// clip" because some Samsung firmware routes a long-press on the
  /// pause button through these callbacks. We override both to no-ops so
  /// only the explicit `skipToNext` / `skipToPrevious` buttons can advance
  /// the playlist. The in-app scrub bar uses precise `seek(position)`
  /// instead, so this doesn't lose any user-facing functionality.
  @override
  Future<void> seekForward(bool begin) async {}

  @override
  Future<void> seekBackward(bool begin) async {}

  @override
  Future<void> fastForward() async {}

  @override
  Future<void> rewind() async {}

  @override
  Future<void> stop() async {
    if (_playingClip) {
      try {
        await stopClip();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('stop: stopClip failed: $e\n$st');
        }
      }
      try {
        onStopClipRequested?.call();
      } catch (_) {}
      return;
    }
    try {
      onStopRequested?.call();
    } catch (_) {}
    // Do NOT call super.stop() here either — same OEM activity-kill
    // hazard as stopClip's standalone branch. If the user toggled Active
    // off, `_audio.exitForeground()` already published the
    // empty/teardown playback state, so the persistent notification
    // fades on its own. Calling super.stop() risks closing the entire
    // app on Samsung / Vivo.
    if (kDebugMode) {
      debugPrint('stop: keep-alive teardown — skipping super.stop() '
          'to avoid OEM activity-kill');
    }
  }

  /// Called by audio_service when the user swipes the app away from the
  /// recent-apps stack. THE DEFAULT base implementation is a no-op, but
  /// `audio_service` would also tear down the MediaSession a few ms later
  /// because our silence loop is just `playing: true` on an idle source —
  /// some OEM heuristics (Vivo, Samsung) misclassify it as "user is done,
  /// kill the service". We explicitly:
  ///   1. Keep the keep-alive silence loop running.
  ///   2. Re-publish `playing: true` so audio_service stays in the
  ///      foreground (this is what tells the OS "this service is still
  ///      doing useful work").
  ///   3. Ping our native [KeepAliveService] to ensure the wake lock is
  ///      still held, even if the activity-managed call to it during
  ///      `toggleActive` was reaped along with the activity.
  ///
  /// Round 19: the user's exact QA "WHEN I CLOSED THE APP then the
  /// AUDIO PROCESS WAS KILLED AND COULDN't HEAR ANYTHING" was the
  /// service quietly demoting itself here. Without this override the
  /// schedule engine was dead inside 60 s of the user swiping the app.
  @override
  Future<void> onTaskRemoved() async {
    if (_keepAlive && !_playingClip) {
      try {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.ready,
            playing: true,
          ),
        );
      } catch (_) {}
      try {
        await _startIdleKeepAlive();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('onTaskRemoved: keep-alive restart failed: $e\n$st');
        }
      }
    }
  }

  /// Called when the user swipes the WhisperBack media notification away.
  /// The base implementation calls `stop()` — but for our keep-alive
  /// architecture that would prematurely tear down the silence loop and
  /// let the OS reap the FG service.
  ///
  /// Branch on Active:
  ///   - Active ON: rebuild the silence loop and republish a `playing:
  ///     true` state so the lock-screen card and the FG binding both
  ///     come back. The user's intent was almost certainly "remove that
  ///     notification card", not "stop scheduling".
  ///   - Active OFF: honor the swipe — call super.onNotificationDeleted
  ///     so the service tears down cleanly.
  @override
  Future<void> onNotificationDeleted() async {
    if (_keepAlive) {
      try {
        await _startIdleKeepAlive();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('onNotificationDeleted: keep-alive restart failed: '
              '$e\n$st');
        }
      }
      return;
    }
    await super.onNotificationDeleted();
  }

  @override
  Future<void> skipToNext() async {
    if (!_playingClip) return;

    if (_playlistMode) {
      await onSkipToNextRequested?.call();
      return;
    }

    // Single-clip context (library preview or one-track playlist):
    // restart from the top instead of silently doing nothing — matches
    // the in-app mini-player + modal behaviour after Round 9 and keeps
    // the lock-screen "next" button feeling alive.
    await _player.seek(Duration.zero);
    if (!_player.playing) {
      await play();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_playingClip) return;

    if (_playlistMode) {
      await onSkipToPreviousRequested?.call();
      return;
    }

    await _player.seek(Duration.zero);
    if (!_player.playing) {
      await play();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'stop_clip':
        onStopClipRequested?.call();
        return;
      case 'power_off':
        onStopRequested?.call();
        return;
    }
  }

  /// Broadcasts state to the system notification + lock screen (official pattern).
  void _broadcastState(PlaybackEvent event) {
    if (!_playingClip) return;
    _publishClipControls(
      playing: _player.playing,
      processing: _player.processingState,
    );
  }

  static const _stopControl = MediaControl(
    androidIcon: 'drawable/ic_media_stop',
    label: 'Stop',
    action: MediaAction.stop,
  );

  void _publishClipControls({
    required bool playing,
    required ProcessingState processing,
  }) {
    final loading = processing == ProcessingState.loading ||
        processing == ProcessingState.buffering;
    final completed = processing == ProcessingState.completed;
    final reportPlaying = !completed && (playing || loading);

    // CRITICAL: the controls array must keep the SAME positions for the
    // same logical buttons across loading / playing / completed states.
    // Previously the play/pause entry was dropped on completion, which
    // shifted `skipToNext` into the compact-bar slot where pause used to
    // be — users tapped what looked like a pause icon and got "next clip"
    // instead. Always render a play/pause entry at index 1 (use `play`
    // when paused, completed, or finished so the icon never disappears).
    final MediaControl playPauseControl =
        reportPlaying ? MediaControl.pause : MediaControl.play;

    // ALWAYS expose [prev, play/pause, next, stop] so the user sees the
    // same 4-button layout on the lock screen and in our in-app mini-
    // player / modal, regardless of whether the source is a single
    // imported clip or a multi-clip playlist. For a single-clip context,
    // tapping next/previous restarts the clip from `Duration.zero` (the
    // coordinator's `_skipPlaylistClip` handles the one-track case),
    // which feels like a natural "restart" instead of a broken button.
    //
    // Previously the non-playlist branch dropped `skipToNext`, which the
    // QA reported as "the notification only shows pause and previous,
    // there is no next button". Now consistent across all contexts.
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      playPauseControl,
      MediaControl.skipToNext,
      _stopControl,
    ];
    const compactIndices = [0, 1, 2];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        // Deliberately do NOT publish `seekForward` / `seekBackward` here.
        // On Samsung One UI 6 + Android 13/14 those system actions are
        // mapped to a 30-second jump that, applied to a short whisper clip,
        // sails past the end and triggers `processingState.completed` — the
        // coordinator's natural-completion handler then auto-advances to
        // the next track. The user reports this as "pause triggers next
        // clip", because the OS sometimes routes a long-press on pause
        // through these actions. We still publish `seek` for the scrubber
        // in our own in-app modal (which uses precise positions), plus
        // `skipToNext` / `skipToPrevious` for the explicit lock-screen
        // buttons — neither involves fast-forward.
        systemActions: const {
          MediaAction.seek,
          MediaAction.stop,
          MediaAction.pause,
          MediaAction.play,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: compactIndices,
        processingState: completed
            ? AudioProcessingState.completed
            : (loading
                ? AudioProcessingState.loading
                : _mapProcessingState(processing)),
        playing: reportPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  void disposePlayer() {
    _startWatchdog?.cancel();
    _startWatchdog = null;
    _player.dispose();
  }
}
