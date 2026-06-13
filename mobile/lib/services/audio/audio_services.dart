import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../../data/repositories/clip_repository.dart';
import 'whisper_audio_handler.dart';

class AudioRecordingService {
  AudioRecordingService(this._clipRepository);

  final ClipRepository _clipRepository;
  final _recorder = AudioRecorder();
  final _uuid = const Uuid();

  Stream<Amplitude>? get amplitudeStream => _recorder
      .isRecording()
      .then((r) => r
          ? _recorder.onAmplitudeChanged(const Duration(milliseconds: 100))
          : null)
      .asStream()
      .asyncExpand((s) => s ?? const Stream.empty());

  Future<bool> get isRecording => _recorder.isRecording();

  Future<AudioClip> startRecording(String title) async {
    final dir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory(p.join(dir.path, 'clips'));
    if (!await clipsDir.exists()) await clipsDir.create(recursive: true);
    final filePath = p.join(clipsDir.path, '${_uuid.v4()}.m4a');

    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
      path: filePath,
    );
    _pendingPath = filePath;
    _pendingTitle = title;
    return AudioClip(
      id: 'pending',
      title: title,
      filePath: filePath,
      durationMs: 0,
      createdAt: DateTime.now(),
      source: ClipSource.recorded,
    );
  }

  String? _pendingPath;
  String? _pendingTitle;

  Future<AudioClip?> stopAndSave() async {
    final path = await _recorder.stop();
    final filePath = path ?? _pendingPath;
    final title = _pendingTitle ?? 'Recording';
    _pendingPath = null;
    _pendingTitle = null;
    if (filePath == null) return null;

    final player = AudioPlayer();
    await player.setFilePath(filePath);
    final durationMs = player.duration?.inMilliseconds ?? 0;
    await player.dispose();

    return _clipRepository.create(
      title: title,
      filePath: filePath,
      durationMs: durationMs,
      source: ClipSource.recorded,
    );
  }

  Future<void> cancel() async {
    await _recorder.stop();
    if (_pendingPath != null) {
      final f = File(_pendingPath!);
      if (await f.exists()) await f.delete();
    }
    _pendingPath = null;
    _pendingTitle = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}

class AudioImportService {
  AudioImportService(this._clipRepository);

  final ClipRepository _clipRepository;
  final _uuid = const Uuid();

  Stream<double> importFile(String sourcePath, String title) async* {
    yield 0.1;
    final dir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory(p.join(dir.path, 'clips'));
    if (!await clipsDir.exists()) await clipsDir.create(recursive: true);

    final ext = p.extension(sourcePath);
    final destPath = p.join(clipsDir.path, '${_uuid.v4()}$ext');
    yield 0.3;

    await File(sourcePath).copy(destPath);
    yield 0.7;

    final player = AudioPlayer();
    await player.setFilePath(destPath);
    final durationMs = player.duration?.inMilliseconds ?? 0;
    await player.dispose();
    yield 0.9;

    await _clipRepository.create(
      title: title,
      filePath: destPath,
      durationMs: durationMs,
      source: ClipSource.imported,
    );
    yield 1.0;
  }
}

/// Thin facade over [WhisperAudioHandler] so the rest of the app is unaware of
/// audio_service. All main playback flows through the handler → foreground
/// service → background playback + media notification.
class AudioPlaybackService {
  AudioPlaybackService(this._handler);

  final WhisperAudioHandler _handler;
  String? _currentPath;

  AudioPlayer get player => _handler.player;

  Stream<Duration?> get positionStream => _handler.player.positionStream;
  Stream<Duration?> get durationStream => _handler.player.durationStream;
  Stream<PlayerState> get playerStateStream => _handler.player.playerStateStream;

  Future<void> playFile(
    String path, {
    String title = 'WhisperBack',
    String? playlistName,
    String? subtitle,
    bool playlistMode = false,
  }) async {
    _currentPath = path;
    await _handler.playFile(
      path,
      title: title,
      playlistName: playlistName,
      subtitle: subtitle,
      playlistMode: playlistMode,
    );
  }

  Future<void> pause() => _handler.pause();
  Future<void> resume() => _handler.play();

  /// Stops the current clip (internal). Resumes the silent keep-alive if the
  /// foreground session is still active.
  Future<void> stop() async {
    await _handler.stopClip();
    _currentPath = null;
  }

  /// Starts the always-on foreground session (master toggle ON).
  Future<void> enterForeground() => _handler.enterForeground();

  Future<void> updateActiveSessionInfo() => _handler.updateActiveSessionInfo();

  set onStopClipRequested(void Function()? cb) =>
      _handler.onStopClipRequested = cb;
  set onPlayRequested(void Function()? cb) => _handler.onPlayRequested = cb;
  set onPauseRequested(void Function()? cb) => _handler.onPauseRequested = cb;
  set onSkipToNextRequested(void Function()? cb) =>
      _handler.onSkipToNextRequested = cb;
  set onSkipToPreviousRequested(void Function()? cb) =>
      _handler.onSkipToPreviousRequested = cb;

  /// Tears down the foreground session (master toggle OFF).
  Future<void> exitForeground() async {
    await _handler.exitForeground();
    _currentPath = null;
  }

  /// Wire the media-notification Stop button to a callback (e.g. toggle OFF).
  set onStopRequested(void Function()? cb) => _handler.onStopRequested = cb;

  bool get isPlaying => _handler.player.playing;
  String? get currentPath => _currentPath;

  /// The handler lives for the whole app lifecycle; nothing to dispose here.
  void dispose() {}
}
