import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/audio_clip.dart';
import '../../data/repositories/clip_repository.dart';
import 'clip_path_guard.dart';
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

    // Stamp the pending state BEFORE calling `_recorder.start` so that if the
    // OS throws (mic permission revoked mid-flight, FGS denied on Android 14,
    // disk full) we still know which file to clean up. Previously the throw
    // happened before `_pendingPath` was set and we leaked an empty `.m4a`.
    _pendingPath = filePath;
    _pendingTitle = title;
    try {
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
        path: filePath,
      );
    } catch (e) {
      _pendingPath = null;
      _pendingTitle = null;
      // Try to remove the partial file `record` may have created; best-effort
      // so the orphan sweep on next bootstrap will handle anything we miss.
      try {
        final partial = File(filePath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      rethrow;
    }
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
    // Snapshot the pending state into locals up front but DO NOT null the
    // instance fields yet — if DB create fails we use them to clean up the
    // orphan file. The old code cleared them eagerly and the file was lost
    // forever on the failure path.
    final pendingPath = _pendingPath;
    final pendingTitle = _pendingTitle ?? 'Recording';
    final stopPath = await _recorder.stop();
    final filePath = stopPath ?? pendingPath;
    if (filePath == null) {
      _pendingPath = null;
      _pendingTitle = null;
      return null;
    }

    AudioClip? created;
    try {
      // CRITICAL: do NOT spin up a probe `AudioPlayer().setFilePath(...)` to
      // measure duration here. On Samsung One UI 12+ that probe player binds
      // to the shared `AudioSession` and either:
      //   (a) silently consumes audio focus so the very next *real* play
      //       call from the user is silently dropped by the OS — this is the
      //       "first recorded clip won't play, the next 6 do" bug; or
      //   (b) auto-starts playback through the foreground media session,
      //       so the user hears their import/recording immediately. Both
      //       were reproduced on the QA device.
      // Duration is cosmetic ("playlist total length"); we leave it as 0
      // here and let `ClipDurationProbe` (a stand-alone, off-session helper)
      // fill it in lazily without touching the playback path. If the lazy
      // probe never runs (rare), the clip still plays fine — duration is
      // discovered when the user hits Play.
      final normalizedTitle =
          pendingTitle.trim().isEmpty ? 'Recording' : pendingTitle.trim();
      created = await _clipRepository.create(
        title: normalizedTitle,
        filePath: filePath,
        durationMs: 0,
        source: ClipSource.recorded,
      );
      _pendingPath = null;
      _pendingTitle = null;
      // Best-effort backfill of duration AFTER the row is committed. Failure
      // is silent — the clip remains playable, just without a length badge.
      unawaited(_clipRepository.backfillDuration(created.id, filePath));
      return created;
    } catch (e) {
      // DB write failed — delete the partial file so we don't leak a
      // recording the user will never be able to access, then surface the
      // error so the UI can show a real toast (not silent failure).
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _pendingPath = null;
      _pendingTitle = null;
      rethrow;
    }
  }

  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // Stop on an idle recorder throws on some OEMs — swallow so cancel()
      // is always safe to call (e.g. from Navigator.didPopRoute).
    }
    if (_pendingPath != null) {
      final f = File(_pendingPath!);
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _pendingPath = null;
    _pendingTitle = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}

/// Removes audio files in the sandbox `clips/` directory that no longer have
/// a matching row in the `clips` table. This handles:
///
/// * Process death mid-recording → orphan `.m4a` left by `record` plugin.
/// * `stopAndSave` write succeeds but `_clipRepository.create` fails after a
///   crash (rare but real on devices with intermittent SQLite locks).
/// * Manual file deletes from external file managers (uncommon, but cheap to
///   handle).
///
/// Called once during bootstrap. Best-effort: any failure is logged and the
/// app keeps starting.
Future<void> reconcileOrphanClipFiles(ClipRepository clipRepository) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory(p.join(dir.path, 'clips'));
    if (!await clipsDir.exists()) return;
    final known = (await clipRepository.getAll())
        .map((c) => p.normalize(c.filePath))
        .toSet();
    final entries = await clipsDir.list().toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final normalized = p.normalize(entry.path);
      if (known.contains(normalized)) continue;
      // Don't blow away non-audio files just in case; only known clip
      // extensions are eligible for cleanup.
      final ext = p.extension(normalized).toLowerCase();
      if (ext != '.m4a' && ext != '.mp3' && ext != '.aac' && ext != '.wav') {
        continue;
      }
      try {
        await entry.delete();
        if (kDebugMode) {
          debugPrint('Cleaned orphan clip file: ${entry.path}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to clean orphan clip ${entry.path}: $e');
        }
      }
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('reconcileOrphanClipFiles failed: $e\n$st');
    }
  }
}

class AudioImportService {
  AudioImportService(this._clipRepository);

  final ClipRepository _clipRepository;
  final _uuid = const Uuid();

  /// Copies a picked audio file into the app sandbox and creates a DB row.
  ///
  /// [sourcePath] is the file system path returned by the picker — may be
  /// `null` on Android 10+ scoped storage. When `null`, [sourceBytes] **must**
  /// carry the file contents (use `file_picker`'s `withData: true`).
  /// [fileName] is the original display name and is required to derive the
  /// extension when [sourcePath] is unavailable.
  Stream<double> importFile(
    String? sourcePath,
    String title, {
    Uint8List? sourceBytes,
    String? fileName,
  }) async* {
    final referenceName = fileName ?? sourcePath ?? '';
    if (!ClipPathGuard.isAllowedImportExtension(referenceName)) {
      throw ArgumentError('Only MP3 and M4A files are supported');
    }
    if (sourcePath == null && (sourceBytes == null || sourceBytes.isEmpty)) {
      throw ArgumentError('Picked file has no readable contents');
    }
    yield 0.1;
    final dir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory(p.join(dir.path, 'clips'));
    if (!await clipsDir.exists()) await clipsDir.create(recursive: true);

    final ext = p.extension(referenceName).toLowerCase();
    final destPath = p.join(clipsDir.path, '${_uuid.v4()}$ext');
    yield 0.3;

    if (sourcePath != null && File(sourcePath).existsSync()) {
      await File(sourcePath).copy(destPath);
    } else {
      // Scoped-storage fallback: write the in-memory bytes the picker handed
      // us. This is the path Samsung devices on Android 10+ frequently take
      // because the OS returns a content:// URI with no real file path.
      await File(destPath).writeAsBytes(sourceBytes!, flush: true);
    }
    yield 0.9;

    // CRITICAL: do NOT spin up a probe `AudioPlayer().setFilePath(...)` to
    // measure duration here. That is what made imported clips start playing
    // immediately on Samsung devices — the probe player binds to the shared
    // foreground `AudioSession` and the OS routes its decoded output to
    // the active media session. Duration is backfilled lazily by
    // `ClipRepository.backfillDuration` AFTER the row is committed, on an
    // isolated player whose session is destroyed before any user-driven
    // playback can race with it.
    final created = await _clipRepository.create(
      title: title,
      filePath: destPath,
      durationMs: 0,
      source: ClipSource.imported,
    );
    yield 0.95;
    unawaited(_clipRepository.backfillDuration(created.id, destPath));
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
  Stream<PlayerState> get playerStateStream =>
      _handler.player.playerStateStream;

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

  /// Hides the lock-screen media card without tearing down the audio
  /// session. Used by `dismissPlayer` so the user's "cross icon" tap
  /// removes the visible system notification too — without that,
  /// pausing leaves the media card hovering on the lock-screen
  /// indefinitely which the user perceives as "the player didn't
  /// really close".
  Future<void> hideClipMediaNotification() =>
      _handler.hideClipMediaNotification();

  /// Seeks the currently playing clip to [position]. Safe no-op when nothing is
  /// playing (e.g. silent keep-alive) — we only forward the request while a
  /// real clip is active so we never scrub the loop.
  Future<void> seek(Duration position) async {
    if (!_handler.isPlayingClip) return;
    await _handler.seek(position);
  }

  /// Stops the current clip (internal). Resumes the silent keep-alive if the
  /// foreground session is still active.
  Future<void> stop() async {
    await _handler.stopClip();
    _currentPath = null;
  }

  /// Starts the always-on foreground session (master toggle ON).
  Future<void> enterForeground() => _handler.enterForeground();

  Future<void> updateActiveSessionInfo() => _handler.updateActiveSessionInfo();

  /// Pause the Dart silence loop while native MediaPlayer owns the clip.
  Future<void> suspendSilenceForExternalPlayback() =>
      _handler.suspendSilenceForExternalPlayback();

  /// Restore the Dart silence loop after native MediaPlayer finishes.
  Future<void> resumeSilenceAfterExternalPlayback() =>
      _handler.resumeSilenceAfterExternalPlayback();

  set onStopClipRequested(void Function()? cb) =>
      _handler.onStopClipRequested = cb;
  set onPlayRequested(void Function()? cb) => _handler.onPlayRequested = cb;
  set onPauseRequested(void Function()? cb) => _handler.onPauseRequested = cb;
  set onSkipToNextRequested(Future<void> Function()? cb) =>
      _handler.onSkipToNextRequested = cb;
  set onSkipToPreviousRequested(Future<void> Function()? cb) =>
      _handler.onSkipToPreviousRequested = cb;
  set onClipSessionChanged(void Function()? cb) =>
      _handler.onClipSessionChanged = cb;
  set onPlaybackStartFailure(void Function(String? clipTitle)? cb) =>
      _handler.onPlaybackStartFailure = cb;

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
