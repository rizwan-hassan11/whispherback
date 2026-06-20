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

  Future<void> _ensureAudioSession() async {
    if (_audioSessionReady) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioSessionReady = true;
  }

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
    await _ensureAudioSession();
    final session = await AudioSession.instance;
    await session.setActive(true);

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
    await _player.setAudioSource(AudioSource.file(path), preload: true);
    onClipSessionChanged?.call();
    await play();
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

    final List<MediaControl> controls;
    List<int> compactIndices;

    if (_playlistMode) {
      controls = [
        MediaControl.skipToPrevious,
        if (!completed && reportPlaying)
          MediaControl.pause
        else if (!completed)
          MediaControl.play,
        MediaControl.skipToNext,
        _stopControl,
      ];
      compactIndices = const [0, 1, 2];
    } else {
      controls = [
        MediaControl.skipToPrevious,
        if (!completed && reportPlaying)
          MediaControl.pause
        else if (!completed)
          MediaControl.play,
        _stopControl,
      ];
      compactIndices = const [0, 1];
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.stop,
          MediaAction.pause,
          MediaAction.play,
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
    _player.dispose();
  }
}
