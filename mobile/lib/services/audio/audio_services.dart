import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../../data/repositories/clip_repository.dart';

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

class AudioPlaybackService {
  AudioPlaybackService();

  final _player = AudioPlayer();
  String? _currentPath;

  AudioPlayer get player => _player;

  Stream<Duration?> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> playFile(String path) async {
    _currentPath = path;
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() async {
    await _player.stop();
    _currentPath = null;
  }

  bool get isPlaying => _player.playing;
  String? get currentPath => _currentPath;

  void dispose() {
    _player.dispose();
  }
}
