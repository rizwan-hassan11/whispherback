import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
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
    _player.playbackEventStream.listen(_broadcastState);
    _player.durationStream.listen(_onDurationReady);
  }

  /// All clip / playlist playback — drives lock-screen + notification controls.
  final AudioPlayer _player = AudioPlayer();

  /// Silent loop (volume 0) while Active + idle — scheduling keep-alive only.
  final AudioPlayer _idlePlayer = AudioPlayer();

  AudioPlayer get player => _player;

  bool _keepAlive = false;
  bool _standalonePlayback = false;
  bool _audioSessionReady = false;
  bool _playingClip = false;
  bool _playlistMode = false;
  String? _silencePath;

  String _sessionSubtitle = 'Listening for scheduled whispers';
  int _scheduleCount = 0;
  String? _clipTitle;

  void Function()? onStopRequested;
  void Function()? onStopClipRequested;
  void Function()? onPlayRequested;
  void Function()? onPauseRequested;
  void Function()? onSkipToNextRequested;
  void Function()? onSkipToPreviousRequested;

  bool get isPlayingClip => _playingClip;
  String? get currentClipTitle => _clipTitle;

  Future<void> _ensureAudioSession() async {
    if (_audioSessionReady) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioSessionReady = true;
  }

  // ── Active session (scheduling keep-alive, no media notification) ───────────

  Future<void> enterForeground({
    String title = 'WhisperBack · Active',
    String subtitle = 'Listening for scheduled whispers',
    int scheduleCount = 0,
  }) async {
    _keepAlive = true;
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_playingClip) return;
    await _startIdleKeepAlive();
  }

  Future<void> _startIdleKeepAlive() async {
    try {
      final path = await _ensureSilenceFile();
      await _idlePlayer.stop();
      await _idlePlayer.setVolume(0);
      await _idlePlayer.setLoopMode(LoopMode.one);
      await _idlePlayer.setAudioSource(AudioSource.file(path));
      await _idlePlayer.play();
    } catch (_) {
      // Scheduling still works in foreground; keep-alive is best-effort.
    }
  }

  Future<void> updateActiveSessionInfo({
    required String subtitle,
    int scheduleCount = 0,
  }) async {
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_playingClip) return;
    if (_keepAlive && !_idlePlayer.playing) {
      await _startIdleKeepAlive();
    }
  }

  Future<void> exitForeground() async {
    _keepAlive = false;
    _playingClip = false;
    _standalonePlayback = false;
    _playlistMode = false;
    _clipTitle = null;
    await _idlePlayer.stop();
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

    await _idlePlayer.stop();

    final item = _clipMediaItem(
      path: path,
      title: title,
      playlistName: playlistName,
      subtitle: subtitle,
    );
    mediaItem.add(item);
    queue.add([item]);

    await _player.setVolume(1);
    await _player.setSpeed(1);
    await _player.setLoopMode(LoopMode.off);
    await _player.setAudioSource(AudioSource.file(path), preload: true);
    await play();
  }

  MediaItem _clipMediaItem({
    required String path,
    required String title,
    String? playlistName,
    String? subtitle,
    Duration? duration,
  }) {
    final line = subtitle ?? 'Now playing';
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
    _playingClip = false;
    _clipTitle = null;
    _playlistMode = false;
    await _player.stop();

    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );

    if (_keepAlive) {
      _standalonePlayback = false;
      await _startIdleKeepAlive();
      return;
    }

    if (_standalonePlayback) {
      _standalonePlayback = false;
      queue.add([]);
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
    await _player.play();
    onPlayRequested?.call();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    onPauseRequested?.call();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    if (_playingClip) {
      onStopClipRequested?.call();
    } else {
      onStopRequested?.call();
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_playlistMode && onSkipToNextRequested != null) {
      onSkipToNextRequested!.call();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlistMode && onSkipToPreviousRequested != null) {
      onSkipToPreviousRequested!.call();
    } else {
      onStopClipRequested?.call();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'stop_clip':
        onStopClipRequested?.call();
      case 'power_off':
        onStopRequested?.call();
    }
  }

  /// Broadcasts state to the system notification + lock screen (official pattern).
  void _broadcastState(PlaybackEvent event) {
    if (!_playingClip) return;

    final playing = _player.playing;
    final processingState = _mapProcessingState(_player.processingState);

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          if (_playlistMode) MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.stop,
          MediaAction.pause,
          MediaAction.play,
        },
        androidCompactActionIndices: _playlistMode
            ? const [0, 1, 3]
            : const [0, 1, 2],
        processingState: processingState,
        playing: playing,
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
    _idlePlayer.dispose();
  }
}
