import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../l10n/runtime_copy.dart';
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
    _player.playbackEventStream.listen(_broadcastState);
    _player.durationStream.listen(_onDurationReady);
    _player.positionStream.listen((_) {
      if (_playingClip && _player.playing) {
        _publishClipControls(
          playing: true,
          processing: _player.processingState,
        );
      }
    });
  }

  /// Silent loop while Active + idle — drives the audio_service foreground service.
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  bool _keepAlive = false;
  bool _standalonePlayback = false;
  bool _audioSessionReady = false;
  bool _playingClip = false;
  bool _playlistMode = false;
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
  bool get isForegroundNotificationActive =>
      whisperAudioServiceBound &&
      isKeepAliveActive &&
      _player.playing &&
      mediaItem.value != null;
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

  // ── Active session (scheduling keep-alive, no media notification) ───────────

  Future<void> enterForeground() async {
    _keepAlive = true;
    if (_playingClip) return;
    await _startIdleKeepAlive();
  }

  Future<void> _startIdleKeepAlive() async {
    if (_playingClip) return;
    try {
      await _ensureAudioSession();
      final session = await AudioSession.instance;
      await session.setActive(true);

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

      await _player.setVolume(0);
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
    } catch (_) {
      // OS alarms still fire if keep-alive fails; scheduling is best-effort here.
    }
  }

  Future<void> updateActiveSessionInfo() async {
    if (_playingClip) return;
    if (_keepAlive && !_player.playing) {
      await _startIdleKeepAlive();
    }
  }

  Future<void> exitForeground() async {
    _keepAlive = false;
    _playingClip = false;
    _standalonePlayback = false;
    _playlistMode = false;
    _clipTitle = null;
    await _player.stop();
    queue.add([]);
    await super.stop();
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
    await _player.stop();
    mediaItem.add(null);
    queue.add([]);

    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );

    onClipSessionChanged?.call();

    if (_keepAlive) {
      _standalonePlayback = false;
      await _startIdleKeepAlive();
      return;
    }

    if (_standalonePlayback) {
      _standalonePlayback = false;
      await super.stop();
    }
  }

  Future<String> _ensureSilenceFile() async {
    if (_silencePath != null && File(_silencePath!).existsSync()) {
      return _silencePath!;
    }
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'whisperback_session_silence.wav'));
    if (!file.existsSync()) {
      await file.writeAsBytes(_silentWav());
    }
    _silencePath = file.path;
    return file.path;
  }

  Uint8List _silentWav({int seconds = 1, int sampleRate = 44100}) {
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

    await _ensureAudioSession();
    final session = await AudioSession.instance;
    await session.setActive(true);

    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }

    _publishClipControls(
      playing: true,
      processing: _player.processingState,
    );

    try {
      await _player.play();
      onPlayRequested?.call();
    } catch (_) {
      _publishClipControls(
        playing: false,
        processing: _player.processingState,
      );
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    if (!_playingClip) return;

    _publishClipControls(
      playing: false,
      processing: _player.processingState,
    );

    await _player.pause();
    onPauseRequested?.call();
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
      await stopClip();
      onStopClipRequested?.call();
      return;
    }
    onStopRequested?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (!_playingClip || !_playlistMode) return;
    await onSkipToNextRequested?.call();
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

    final List<MediaControl> controls;
    List<int> compactIndices;

    if (_playlistMode) {
      controls = [
        MediaControl.skipToPrevious,
        playPauseControl,
        MediaControl.skipToNext,
        _stopControl,
      ];
      compactIndices = const [0, 1, 2];
    } else {
      controls = [
        MediaControl.skipToPrevious,
        playPauseControl,
        _stopControl,
      ];
      compactIndices = const [0, 1];
    }

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
