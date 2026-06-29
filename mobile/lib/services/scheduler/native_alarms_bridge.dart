// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/playlist_repository.dart';
import '../../domain/entities/playback_schedule.dart';
import 'schedule_fire_helper.dart';
import 'schedule_last_fired_store.dart';

/// Round 22 — playback-state values emitted by the native
/// `WhisperPlaybackService` to the Dart side. Must match the constants in
/// `WhisperPlaybackService.kt` (STATE_IDLE / STATE_PLAYING / STATE_PAUSED).
class NativePlaybackState {
  static const String idle = 'idle';
  static const String playing = 'playing';
  static const String paused = 'paused';
}

/// Snapshot of the native playback service's current state. Emitted on
/// every transition (start / pause / resume / stop) AND polled by the
/// Dart side on app launch / resume so the mini-player can light up
/// even for a scheduled clip that started while the app was closed.
@immutable
class NativePlaybackSnapshot {
  const NativePlaybackSnapshot({
    required this.state,
    this.clipPath,
    this.clipTitle,
    this.playlistName,
    this.scheduleId,
  });

  factory NativePlaybackSnapshot.idle() => const NativePlaybackSnapshot(
        state: NativePlaybackState.idle,
      );

  final String state;
  final String? clipPath;
  final String? clipTitle;
  final String? playlistName;
  final String? scheduleId;

  bool get isPlaying => state == NativePlaybackState.playing;
  bool get isPaused => state == NativePlaybackState.paused;
  bool get isIdle => state == NativePlaybackState.idle;
  bool get hasClip => (clipPath ?? '').isNotEmpty;
}

/// Round 21 — bridge to the native Android alarm-clock scheduler.
///
/// The native side (Kotlin `WhisperAlarmScheduler`) owns the actual
/// `AlarmManager` table. This Dart helper turns the user's
/// `PlaybackSchedule` list into a JSON snapshot of upcoming fires and
/// ships it across the platform channel. The native side then registers
/// one `setAlarmClock` PendingIntent per fire; when an alarm fires it
/// starts a typed `mediaPlayback` foreground service that plays the
/// resolved clip.
///
/// We refresh the snapshot on:
///   • App start
///   • Active toggle on/off
///   • Schedule create / update / delete
///   • App resume (in case the user changed system time/timezone)
///   • Every successful scheduled fire (advances the "completed" cursor)
///
/// We cap the snapshot at [_kMaxFiresPerSchedule] fires per schedule and
/// [_kMaxFiresTotal] fires overall, so a hyper-active schedule doesn't
/// crowd out the others. The native scheduler ALSO enforces a 192-alarm
/// hard cap as a safety net.
class NativeAlarmsBridge {
  NativeAlarmsBridge._() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_onMethodCall);
    }
  }
  static final NativeAlarmsBridge instance = NativeAlarmsBridge._();

  static const MethodChannel _channel = MethodChannel('com.whisperback.alarms');

  /// Up to ~24 hours of fires per schedule (1-minute schedules cap at 1440;
  /// the snapshot cap of 24 plays nicely with our typical 30/60-minute
  /// intervals while letting fine-grained schedules survive overnight).
  static const int _kMaxFiresPerSchedule = 48;
  static const int _kMaxFiresTotal = 180;

  /// Broadcasts every native playback state transition to the Dart side.
  /// The `PlaybackCoordinator` subscribes so it can light up the mini-
  /// player when a scheduled clip starts, flip the play/pause icon when
  /// the user uses the notification controls, and tear the snapshot
  /// down when playback finishes / is stopped.
  final StreamController<NativePlaybackSnapshot> _stateController =
      StreamController<NativePlaybackSnapshot>.broadcast();
  Stream<NativePlaybackSnapshot> get stateStream => _stateController.stream;

  NativePlaybackSnapshot _lastSnapshot = NativePlaybackSnapshot.idle();
  NativePlaybackSnapshot get lastSnapshot => _lastSnapshot;

  Future<void> _onMethodCall(MethodCall call) async {
    try {
      if (call.method == 'onScheduledPlaybackState') {
        final args = (call.arguments as Map?) ?? const {};
        final snapshot = NativePlaybackSnapshot(
          state: (args['state'] as String?) ?? NativePlaybackState.idle,
          clipPath: args['clipPath'] as String?,
          clipTitle: args['clipTitle'] as String?,
          playlistName: args['playlistName'] as String?,
          scheduleId: args['scheduleId'] as String?,
        );
        _lastSnapshot = snapshot;
        if (!_stateController.isClosed) {
          _stateController.add(snapshot);
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge._onMethodCall failed: $e\n$st');
      }
    }
  }

  Future<void> applySnapshot({
    required Iterable<PlaybackSchedule> schedules,
    required PlaylistRepository playlists,
    required bool active,
  }) async {
    if (!Platform.isAndroid) return;
    if (!active) {
      await cancelAll();
      return;
    }
    final enabled = schedules.where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      await cancelAll();
      return;
    }
    final fires = <Map<String, Object?>>[];
    final now = DateTime.now();
    final lastFired = ScheduleLastFiredStore.instance;
    for (final schedule in enabled) {
      String? clipPath;
      String clipTitle = 'WhisperBack';
      try {
        final list = await playlists.getClips(schedule.playlistId);
        for (final clip in list) {
          final path = clip.filePath;
          if (path.isEmpty) continue;
          if (!await File(path).exists()) continue;
          clipPath = path;
          clipTitle = clip.title.isNotEmpty ? clip.title : clipTitle;
          break;
        }
      } catch (e, st) {
        if (kDebugMode) {
          print('NativeAlarmsBridge: resolve clip for ${schedule.id} failed: $e\n$st');
        }
      }
      if (clipPath == null) continue;
      var lastCompletion = lastFired.completion(schedule.id);
      var lastSlot = lastFired.slot(schedule.id);
      var added = 0;
      var cursor = now;
      while (added < _kMaxFiresPerSchedule) {
        final next = ScheduleFireHelper.nextFireTime(
          schedule,
          cursor,
          lastFired: lastCompletion,
          lastSlot: lastSlot,
          forDisplay: true,
        );
        if (next == null) break;
        if (!next.isAfter(now)) break;
        fires.add({
          'scheduleId': schedule.id,
          'clipPath': clipPath,
          'clipTitle': clipTitle,
          'playlistName':
              schedule.playlistName.isNotEmpty ? schedule.playlistName : 'WhisperBack',
          'fireEpochMs': next.millisecondsSinceEpoch,
        });
        added++;
        lastSlot = next;
        lastCompletion = next.add(Duration(milliseconds: schedule.playlistDurationMs));
        // Move the cursor PAST this slot so the helper returns the next one.
        cursor = next.add(const Duration(seconds: 1));
        if (fires.length >= _kMaxFiresTotal) break;
      }
      if (fires.length >= _kMaxFiresTotal) break;
    }
    fires.sort((a, b) =>
        (a['fireEpochMs']! as int).compareTo(b['fireEpochMs']! as int));
    final json = jsonEncode(fires.take(_kMaxFiresTotal).toList());
    try {
      final registered = await _channel.invokeMethod<int>('setSnapshot', {
        'snapshot': json,
        'active': active,
      });
      if (kDebugMode) {
        print('NativeAlarmsBridge: native registered $registered alarms');
      }
    } on MissingPluginException {
      if (kDebugMode) {
        print('NativeAlarmsBridge: native channel missing (non-Android?)');
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.setSnapshot failed: $e\n$st');
      }
    }
  }

  Future<void> cancelAll() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // Not running on Android — silently ignore.
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.cancelAll failed: $e\n$st');
      }
    }
  }

  /// Pauses the in-flight scheduled clip (no-op if nothing is playing).
  /// The native [WhisperPlaybackService] re-posts its notification with
  /// the RESUME action so the user can resume from the shade.
  Future<void> pauseNative() async {
    await _invokeVoid('pauseNative');
  }

  /// Resumes a paused scheduled clip.
  Future<void> resumeNative() async {
    await _invokeVoid('resumeNative');
  }

  /// Stops the in-flight scheduled clip and tears down the native FG
  /// service. The user can dismiss the playback notification by tapping
  /// "Stop" in the shade, which routes through the same path.
  Future<void> stopNative() async {
    await _invokeVoid('stopNative');
    // Optimistic local snapshot — the listener will also fire from native
    // but we emit immediately so the mini-player can disappear without
    // waiting for the round-trip.
    final snapshot = NativePlaybackSnapshot.idle();
    _lastSnapshot = snapshot;
    if (!_stateController.isClosed) {
      _stateController.add(snapshot);
    }
  }

  /// Pushes the user's preferred playback volume (0.0–1.0) into native
  /// SharedPreferences. The next [WhisperPlaybackService.playClip] picks
  /// it up via `MediaPlayer.setVolume()`. The QA report "schedule plays
  /// at full volume although I set my volume low" is fully fixed by the
  /// combination of switching audio attributes to media usage AND
  /// honoring this slider.
  Future<void> setVolume(double volume) async {
    if (!Platform.isAndroid) return;
    final clamped = volume.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod<void>('setVolume', clamped);
    } on MissingPluginException {
      // Not running on Android — silently ignore.
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.setVolume failed: $e\n$st');
      }
    }
  }

  /// Reads the current native playback state from SharedPreferences. The
  /// Dart side calls this on app launch / resume so the mini-player can
  /// pick up a scheduled clip that started while the Flutter engine was
  /// dead.
  Future<NativePlaybackSnapshot> fetchPlaybackState() async {
    if (!Platform.isAndroid) return NativePlaybackSnapshot.idle();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getPlaybackState');
      if (raw == null) return NativePlaybackSnapshot.idle();
      final snapshot = NativePlaybackSnapshot(
        state: (raw['state'] as String?) ?? NativePlaybackState.idle,
        clipPath: raw['clipPath'] as String?,
        clipTitle: raw['clipTitle'] as String?,
        playlistName: raw['playlistName'] as String?,
        scheduleId: raw['scheduleId'] as String?,
      );
      _lastSnapshot = snapshot;
      if (!_stateController.isClosed) {
        _stateController.add(snapshot);
      }
      return snapshot;
    } on MissingPluginException {
      return NativePlaybackSnapshot.idle();
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.fetchPlaybackState failed: $e\n$st');
      }
      return NativePlaybackSnapshot.idle();
    }
  }

  Future<void> _invokeVoid(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not running on Android — silently ignore.
    } catch (e, st) {
      if (kDebugMode) {
        print('NativeAlarmsBridge.$method failed: $e\n$st');
      }
    }
  }
}
