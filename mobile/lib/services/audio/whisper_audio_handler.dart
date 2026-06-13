import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

WhisperAudioHandler? _whisperAudioHandler;

WhisperAudioHandler get whisperAudioHandler =>
    _whisperAudioHandler ??= WhisperAudioHandler();

set whisperAudioHandler(WhisperAudioHandler handler) =>
    _whisperAudioHandler = handler;

/// Bridges just_audio to audio_service for foreground playback, media
/// notifications, and lock-screen controls.
///
/// Two players: [_sessionPlayer] for the silent keep-alive loop, [_clipPlayer]
/// for all real audio so sample rates never mix on one graph.
class WhisperAudioHandler extends BaseAudioHandler {
  WhisperAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {MediaAction.stop},
        androidCompactActionIndices: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );

    _clipPlayer.playbackEventStream.listen((e) {
      if (_playingClip) _broadcastState(e);
    });
    _sessionPlayer.playbackEventStream.listen((e) {
      if (!_playingClip) _broadcastState(e);
    });
  }

  final AudioPlayer _sessionPlayer = AudioPlayer();
  final AudioPlayer _clipPlayer = AudioPlayer();

  AudioPlayer get player => _clipPlayer;

  bool _keepAlive = false;
  bool _standalonePlayback = false;
  String? _silencePath;

  void Function()? onStopRequested;
  void Function()? onStopClipRequested;
  void Function()? onPlayRequested;
  void Function()? onPauseRequested;

  String _sessionSubtitle = 'Listening for scheduled whispers';
  int _scheduleCount = 0;
  bool _playingClip = false;

  AudioPlayer get _activePlayer => _playingClip ? _clipPlayer : _sessionPlayer;

  // ── Keep-alive foreground session ─────────────────────────────────────────

  Future<void> enterForeground({
    String title = 'WhisperBack · Active',
    String subtitle = 'Listening for scheduled whispers',
    int scheduleCount = 0,
  }) async {
    _keepAlive = true;
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_playingClip) return;
    await _startSessionLoop(title: title);
  }

  Future<void> _startSessionLoop({String title = 'WhisperBack · Active'}) async {
    _playingClip = false;
    mediaItem.add(_activeMediaItem(title: title));
    try {
      final path = await _ensureSilenceFile();
      await _sessionPlayer.stop();
      await _sessionPlayer.setVolume(0);
      await _sessionPlayer.setLoopMode(LoopMode.one);
      await _sessionPlayer.setAudioSource(AudioSource.file(path));
      await _sessionPlayer.play();
    } catch (_) {
      // Still publish media session so the foreground notification appears.
    }
    _broadcastState(null);
  }

  Future<void> updateActiveSessionInfo({
    required String subtitle,
    int scheduleCount = 0,
  }) async {
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_playingClip) {
      // Refresh clip notification subtitle with next-up info when idle again.
      return;
    }
    mediaItem.add(_activeMediaItem());
    if (_keepAlive && !_sessionPlayer.playing) {
      await _startSessionLoop();
    } else {
      _broadcastState(null);
    }
  }

  MediaItem _activeMediaItem({String title = 'WhisperBack · Active'}) {
    final scheduleLine = _scheduleCount > 0
        ? '$_scheduleCount schedule(s) armed'
        : 'No schedules armed';
    return MediaItem(
      id: 'whisperback-active',
      title: title,
      album: 'WhisperBack',
      artist: _sessionSubtitle,
      displayTitle: title,
      displaySubtitle: _sessionSubtitle,
      displayDescription: scheduleLine,
      extras: const {'mode': 'active_idle'},
    );
  }

  Future<void> exitForeground() async {
    _keepAlive = false;
    _playingClip = false;
    _standalonePlayback = false;
    await _sessionPlayer.stop();
    await _clipPlayer.stop();
    await super.stop();
  }

  // ── Clip playback (manual + scheduled) ────────────────────────────────────

  Future<void> playFile(
    String path, {
    String title = 'WhisperBack',
    String? playlistName,
    String? subtitle,
  }) async {
    _playingClip = true;
    if (!_keepAlive) _standalonePlayback = true;

    await _sessionPlayer.stop();

    await _clipPlayer.stop();
    await _clipPlayer.setVolume(1);
    await _clipPlayer.setSpeed(1);
    await _clipPlayer.setLoopMode(LoopMode.off);

    final item = MediaItem(
      id: path,
      title: title,
      album: playlistName ?? 'WhisperBack',
      artist: subtitle ?? 'Now playing',
      displayTitle: title,
      displaySubtitle: playlistName ?? subtitle ?? 'Now playing',
      displayDescription: subtitle ?? 'Now playing',
      extras: const {'mode': 'clip'},
    );
    mediaItem.add(item);

    await _clipPlayer.setAudioSource(
      AudioSource.file(path),
      preload: true,
    );
    await _clipPlayer.play();

    final dur = _clipPlayer.duration;
    if (dur != null) {
      mediaItem.add(
        MediaItem(
          id: item.id,
          title: item.title,
          album: item.album,
          artist: item.artist,
          duration: dur,
          displayTitle: item.displayTitle,
          displaySubtitle: item.displaySubtitle,
          displayDescription: item.displayDescription,
          extras: item.extras,
        ),
      );
    }
    _broadcastState(null);
  }

  Future<void> stopClip() async {
    _playingClip = false;
    await _clipPlayer.stop();

    if (_keepAlive) {
      _standalonePlayback = false;
      await _startSessionLoop();
      return;
    }

    if (_standalonePlayback) {
      _standalonePlayback = false;
      await super.stop();
    }
    _broadcastState(null);
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

  // ── audio_service media controls ──────────────────────────────────────────

  @override
  Future<void> play() async {
    if (_playingClip) {
      await _clipPlayer.play();
      onPlayRequested?.call();
      _broadcastState(null);
      return;
    }
    if (_keepAlive && _sessionPlayer.volume == 0 && !_playingClip) return;
    await _sessionPlayer.play();
    onPlayRequested?.call();
    _broadcastState(null);
  }

  @override
  Future<void> pause() async {
    if (_playingClip) {
      await _clipPlayer.pause();
      onPauseRequested?.call();
      _broadcastState(null);
      return;
    }
    if (_keepAlive && _sessionPlayer.volume == 0) return;
    await _sessionPlayer.pause();
    onPauseRequested?.call();
    _broadcastState(null);
  }

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

  @override
  Future<void> stop() async {
    if (_playingClip) {
      onStopClipRequested?.call();
    } else {
      onStopRequested?.call();
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

  void _broadcastState(PlaybackEvent? event) {
    final active = _activePlayer;
    final playing = active.playing;

    final reportPlaying = _playingClip
        ? playing
        : (_keepAlive || _standalonePlayback || playing);

    final processingState = _playingClip
        ? (playing
            ? AudioProcessingState.ready
            : _mapProcessingState(active.processingState))
        : (_keepAlive
            ? AudioProcessingState.ready
            : _mapProcessingState(active.processingState));

    final controls = <MediaControl>[
      if (_playingClip) ...[
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
      if (_keepAlive)
        MediaControl.custom(
          androidIcon: 'drawable/ic_power',
          label: 'Power off',
          name: 'power_off',
        ),
    ];

    final compact = <int>[];
    if (_playingClip) {
      compact.addAll(List.generate(controls.length.clamp(0, 3), (i) => i));
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: {
          if (_playingClip) MediaAction.seek,
          MediaAction.stop,
        },
        androidCompactActionIndices: compact,
        processingState: processingState,
        playing: reportPlaying,
        updatePosition: active.position,
        bufferedPosition: active.bufferedPosition,
        speed: active.speed,
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
    _sessionPlayer.dispose();
    _clipPlayer.dispose();
  }
}
