import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/feature_flags.dart';

/// Plays the bundled adhan asset once when a prayer window starts.
///
/// Uses its own [AudioPlayer] instance so it never interferes with the
/// foreground keep-alive or media notification state used by whispers. The
/// shared [AudioSession] is reused (Android only allows one); we make sure it
/// is configured and active before playback so the adhan actually outputs even
/// if the main handler hasn't been initialised yet.
class AdhanPlayer {
  AdhanPlayer._();
  static final AdhanPlayer instance = AdhanPlayer._();

  static const String adhanAssetPath = 'assets/audio/adhan.mp3';

  AudioPlayer? _player;
  String? _lastPlayedWindowKey;
  bool _loading = false;

  /// Plays the adhan for [windowKey] (typically the prayer name + start time).
  /// No-op if the same key already played during the current process lifetime.
  Future<void> playFor(String windowKey) async {
    if (!kAdhanFeatureEnabled) return;
    if (_lastPlayedWindowKey == windowKey) return;
    if (_loading) return;
    _loading = true;
    try {
      _lastPlayedWindowKey = windowKey;
      await _ensureSessionActive();
      final player = _player ??= AudioPlayer();
      // setAsset returns the duration; awaiting ensures we don't race play().
      await player.setAsset(adhanAssetPath);
      await player.setVolume(1.0);
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      if (kDebugMode) debugPrint('AdhanPlayer playback failed: $e');
      _lastPlayedWindowKey = null;
    } finally {
      _loading = false;
    }
  }

  Future<void> _ensureSessionActive() async {
    try {
      final session = await AudioSession.instance;
      // Music profile is safe — Android will mix with most other audio.
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      if (kDebugMode) debugPrint('AdhanPlayer session configure failed: $e');
    }
  }

  /// Cancels playback if currently active. Safe to call repeatedly.
  Future<void> stop() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
