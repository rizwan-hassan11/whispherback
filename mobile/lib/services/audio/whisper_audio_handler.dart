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
/// While the master toggle is ON, a silent looping track keeps the foreground
/// service (and therefore the scheduling isolate) alive between intervals so
/// schedules still fire when the app is backgrounded or swiped away — and the
/// ongoing notification signals the OS to keep the process around.
class WhisperAudioHandler extends BaseAudioHandler {
  WhisperAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
  }

  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  /// True while the keep-alive (Active) foreground session is running.
  bool _keepAlive = false;
  String? _silencePath;

  /// Invoked when the user taps Stop while idle — turns master toggle OFF.
  void Function()? onStopRequested;

  /// Invoked when Stop is tapped during clip playback — stops clip only.
  void Function()? onStopClipRequested;

  /// Keep coordinator UI in sync with notification play/pause.
  void Function()? onPlayRequested;
  void Function()? onPauseRequested;

  String _sessionSubtitle = 'Listening for scheduled whispers';
  int _scheduleCount = 0;
  bool _playingClip = false;

  // ── Keep-alive foreground session ─────────────────────────────────────────

  /// Starts the foreground service and holds it open with a silent loop.
  Future<void> enterForeground({
    String title = 'WhisperBack · Active',
    String subtitle = 'Listening for scheduled whispers',
    int scheduleCount = 0,
  }) async {
    _keepAlive = true;
    _playingClip = false;
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    try {
      final path = await _ensureSilenceFile();
      mediaItem.add(_activeMediaItem(title: title));
      await _player.setVolume(0);
      await _player.setLoopMode(LoopMode.one);
      await _player.setFilePath(path);
      await _player.play();
      _broadcastState(null);
    } catch (_) {
      // If silence can't be prepared, the service still runs while clips play.
    }
  }

  /// Updates the idle-session notification text (schedule summary).
  Future<void> updateActiveSessionInfo({
    required String subtitle,
    int scheduleCount = 0,
  }) async {
    _sessionSubtitle = subtitle;
    _scheduleCount = scheduleCount;
    if (_keepAlive && !_playingClip) {
      mediaItem.add(_activeMediaItem());
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
      artist: scheduleLine,
      displayTitle: title,
      displaySubtitle: _sessionSubtitle,
      displayDescription: scheduleLine,
      extras: const {'mode': 'active_idle'},
    );
  }

  /// Tears down the foreground session (master toggle OFF).
  Future<void> exitForeground() async {
    _keepAlive = false;
    _playingClip = false;
    await _player.stop();
    await super.stop();
  }

  /// Plays a real clip, interrupting the silent keep-alive.
  Future<void> playFile(
    String path, {
    String title = 'WhisperBack',
    String? playlistName,
    String? subtitle,
  }) async {
    _playingClip = true;
    mediaItem.add(
      MediaItem(
        id: path,
        title: title,
        album: playlistName ?? 'WhisperBack',
        artist: subtitle ?? 'Now playing',
        displayTitle: title,
        displaySubtitle: playlistName,
        displayDescription: subtitle ?? 'Now playing',
        duration: _player.duration,
        extras: const {'mode': 'clip'},
      ),
    );
    await _player.setVolume(1);
    await _player.setLoopMode(LoopMode.off);
    await _player.setFilePath(path);
    await _player.play();
    final dur = _player.duration;
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

  /// Stops the current clip; resumes the silent keep-alive if still Active.
  Future<void> stopClip() async {
    _playingClip = false;
    await _player.stop();
    if (_keepAlive) await enterForeground(subtitle: _sessionSubtitle);
  }

  Future<String> _ensureSilenceFile() async {
    if (_silencePath != null && File(_silencePath!).existsSync()) {
      return _silencePath!;
    }
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'whisperback_silence.wav'));
    if (!file.existsSync()) {
      await file.writeAsBytes(_silentWav());
    }
    _silencePath = file.path;
    return file.path;
  }

  /// Builds a 1-second silent mono 16-bit PCM WAV (8 kHz) in memory.
  Uint8List _silentWav({int seconds = 1, int sampleRate = 8000}) {
    final numSamples = seconds * sampleRate;
    final dataSize = numSamples * 2;
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
    u32(16); // PCM chunk size
    u16(1); // PCM format
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits per sample
    str('data');
    u32(dataSize);
    bytes.add(Uint8List(dataSize)); // zeros = silence
    return bytes.toBytes();
  }

  // ── audio_service media controls ──────────────────────────────────────────

  @override
  Future<void> play() async {
    if (_keepAlive && _player.volume == 0 && !_playingClip) return;
    await _player.play();
    onPlayRequested?.call();
    _broadcastState(null);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    onPauseRequested?.call();
    _broadcastState(null);
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
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'stop_clip':
        onStopClipRequested?.call();
      case 'power_off':
        onStopRequested?.call();
    }
  }

  void _broadcastState(PlaybackEvent? event) {
    final silentKeepAlive = _keepAlive && _player.volume == 0 && !_playingClip;
    final playing = _player.playing;
    final controls = <MediaControl>[
      if (_playingClip) playing ? MediaControl.pause : MediaControl.play,
      if (_playingClip)
        MediaControl.custom(
          androidIcon: 'drawable/ic_close',
          label: 'Dismiss clip',
          name: 'stop_clip',
        ),
      MediaControl.custom(
        androidIcon: 'drawable/ic_power',
        label: 'Power off',
        name: 'power_off',
      ),
    ];

    final compact = <int>[];
    if (_playingClip) {
      compact.add(0);
      if (controls.length > 2) compact.add(1);
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: {
          if (_playingClip) MediaAction.seek,
          MediaAction.stop,
        },
        androidCompactActionIndices: compact,
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: silentKeepAlive ? false : playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  void disposePlayer() {
    _player.dispose();
  }
}
