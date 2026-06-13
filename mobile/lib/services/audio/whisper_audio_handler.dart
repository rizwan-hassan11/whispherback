import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

WhisperAudioHandler? _whisperAudioHandler;

/// App-wide audio handler instance. Assigned during startup in `main()`.
/// Falls back to a plain handler if accessed before init (e.g. in tests),
/// so the app/tests never crash on a missing handler.
WhisperAudioHandler get whisperAudioHandler =>
    _whisperAudioHandler ??= WhisperAudioHandler();

set whisperAudioHandler(WhisperAudioHandler handler) =>
    _whisperAudioHandler = handler;

/// Bridges just_audio to audio_service so playback runs inside an Android
/// foreground service (background playback + media notification + lock-screen).
///
/// Uses two [AudioPlayer] instances so the silent keep-alive loop never shares
/// an audio graph with real clips — avoids sample-rate switching distortion.
class WhisperAudioHandler extends BaseAudioHandler {
  WhisperAudioHandler() {
    _clipPlayer.playbackEventStream.listen((e) {
      if (_playingClip) _broadcastState(e);
    });
    _sessionPlayer.playbackEventStream.listen((e) {
      if (!_playingClip) _broadcastState(e);
    });
  }

  /// Silent loop that keeps the foreground service alive between intervals.
  final AudioPlayer _sessionPlayer = AudioPlayer();

  /// All user-facing audio (manual preview, playlists, scheduled whispers).
  final AudioPlayer _clipPlayer = AudioPlayer();

  /// Exposed to the rest of the app for progress UI and completion events.
  AudioPlayer get player => _clipPlayer;

  /// True while the keep-alive (Active) foreground session is running.
  bool _keepAlive = false;

  /// True while a clip plays without the master Active toggle (library preview).
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
    try {
      final path = await _ensureSilenceFile();
      mediaItem.add(_activeMediaItem(title: title));
      await _sessionPlayer.setVolume(0);
      await _sessionPlayer.setLoopMode(LoopMode.one);
      await _sessionPlayer.setAudioSource(AudioSource.file(path));
      await _sessionPlayer.play();
      _broadcastState(null);
    } catch (_) {
      // If silence can't be prepared, the service still runs while clips play.
      mediaItem.add(_activeMediaItem(title: title));
      _broadcastState(null);
    }
  }

  Future<void> updateActiveSessionInfo({
    required String subtitle,
    int scheduleCount = 0,
  }) async {
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_playingClip) return;
    if (_keepAlive) {
      mediaItem.add(_activeMediaItem());
      _broadcastState(null);
    } else {
      await enterForeground(
        subtitle: subtitle,
        scheduleCount: scheduleCount,
      );
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
      artist: scheduleLine,
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

    // Fully stop the keep-alive player so clip audio uses a clean graph.
    await _sessionPlayer.stop();

    await _clipPlayer.stop();
    await _clipPlayer.setVolume(1);
    await _clipPlayer.setSpeed(1);
    await _clipPlayer.setLoopMode(LoopMode.off);

    mediaItem.add(
      MediaItem(
        id: path,
        title: title,
        album: playlistName ?? 'WhisperBack',
        artist: subtitle ?? 'Now playing',
        displayTitle: title,
        displaySubtitle: playlistName ?? subtitle,
        displayDescription: subtitle ?? 'Now playing',
        extras: const {'mode': 'clip'},
      ),
    );

    await _clipPlayer.setAudioSource(
      AudioSource.file(path),
      preload: true,
    );
    await _clipPlayer.play();

    final dur = _clipPlayer.duration;
    if (dur != null && mediaItem.value != null) {
      mediaItem.add(
        MediaItem(
          id: mediaItem.value!.id,
          title: mediaItem.value!.title,
          album: mediaItem.value!.album,
          artist: mediaItem.value!.artist,
          duration: dur,
          displayTitle: mediaItem.value!.displayTitle,
          displaySubtitle: mediaItem.value!.displaySubtitle,
          displayDescription: mediaItem.value!.displayDescription,
          extras: mediaItem.value!.extras,
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

  /// 1 s silent stereo PCM WAV at 44.1 kHz — matches typical clip sample rate.
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
    if (_keepAlive && _sessionPlayer.volume == 0) return;
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

    // Keep the media notification + lock-screen controls visible whenever
    // Active is on OR a clip is playing (manual or scheduled).
    final reportPlaying =
        _playingClip ? playing : (_keepAlive || _standalonePlayback || playing);

    final controls = <MediaControl>[
      if (_playingClip) playing ? MediaControl.pause : MediaControl.play,
      if (_playingClip)
        MediaControl.custom(
          androidIcon: 'drawable/ic_close',
          label: 'Dismiss clip',
          name: 'stop_clip',
        ),
      if (_keepAlive)
        MediaControl.custom(
          androidIcon: 'drawable/ic_power',
          label: 'Power off',
          name: 'power_off',
        ),
    ];

    final compact = <int>[];
    if (_playingClip) {
      compact.add(0);
      if (controls.length > 1) compact.add(1);
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: {
          if (_playingClip) MediaAction.seek,
          MediaAction.stop,
        },
        androidCompactActionIndices: compact.isEmpty ? null : compact,
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[active.processingState]!,
        playing: reportPlaying,
        updatePosition: active.position,
        bufferedPosition: active.bufferedPosition,
        speed: active.speed,
        queueIndex: 0,
      ),
    );
  }

  void disposePlayer() {
    _sessionPlayer.dispose();
    _clipPlayer.dispose();
  }
}
