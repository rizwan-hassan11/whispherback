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
/// crowd out the others. The native scheduler ALSO enforces a 400-alarm
/// hard cap as a safety net (Round 23 bump from 192).
class NativeAlarmsBridge {
  NativeAlarmsBridge._() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_onMethodCall);
    }
  }
  static final NativeAlarmsBridge instance = NativeAlarmsBridge._();

  static const MethodChannel _channel = MethodChannel('com.whisperback.alarms');

  /// Round 23 — bumped from 48 to 288 fires per schedule and from 180
  /// to 400 fires total. The old caps were the QA root cause "later
  /// schedules stopped working after a while": if the user set a
  /// 5-minute schedule, 48 fires covered only ~4 hours; the moment the
  /// app was closed for longer than that the alarm table dried up and
  /// no more fires were registered until the user opened the app.
  ///
  /// 288 = one fire every 5 minutes for a full 24 hours per schedule.
  /// 400 total sits comfortably under Android's per-app cap of 500
  /// (we reserve headroom for `flutter_local_notifications` alarms +
  /// prayer alarms).
  ///
  /// A schedule that fires every 30 minutes now has 288 fires ≈ 6 days
  /// of coverage. Combined with the Round 23 "refill on every
  /// completion" logic in `PlaybackCoordinator._onNativePlaybackState`,
  /// the alarm table effectively NEVER dries up.
  static const int _kMaxFiresPerSchedule = 288;
  static const int _kMaxFiresTotal = 400;

  /// Round 24 — STRUCTURAL fingerprint (schedules + clips + active state
  /// only; NEVER fire times). The prior Round-23 fingerprint hashed
  /// projected fire times, which caused a devastating bug: every fire
  /// slightly drifted `lastFired`, which drifted the projected times,
  /// which changed the fingerprint, which forced `applySnapshot` to
  /// cancel EVERY pending alarm and re-register with new times. If a
  /// pending alarm was about to fire (within the 500 ms delivery
  /// latency window), the OS silently dropped it. Combined with the
  /// engine's 5-second notification tick, that meant EVERY fire past
  /// the first was at risk of being cancelled mid-delivery.
  ///
  /// The correct model: the alarm table structure only changes when
  /// the user creates/edits/deletes a schedule, swaps a playlist's
  /// first playable clip, or toggles Active. All other refreshes
  /// (notification card updates, engine ticks, state listener fires)
  /// MUST NOT touch the alarm table.
  String? _lastStructuralFingerprint;

  /// Round 24 — millis at which we last actually re-registered the
  /// alarm table. Used by `refreshTail` to decide whether the tail
  /// might have dried up (e.g. after ~24 h since last register we
  /// should proactively re-register the tail regardless of structure).
  DateTime? _lastRegisteredAt;

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

  @visibleForTesting
  void debugResetFingerprint() {
    _lastStructuralFingerprint = null;
    _lastRegisteredAt = null;
  }

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

  /// Rebuilds the native alarm table.
  ///
  /// Round 24 — this is now guarded by a STRUCTURAL fingerprint. The
  /// alarm table is only cancel-and-re-registered when the STRUCTURE
  /// changes: user added / edited / deleted a schedule, swapped a
  /// playlist's first playable clip, or toggled Active. Everything
  /// else (the 5-second notification tick, state-listener refreshes,
  /// small `lastFired` drift after a fire) is a no-op.
  ///
  /// This closes the Round 23 regression where every fire slightly
  /// changed the projected slots, which drifted the fingerprint,
  /// which forced a cancel+re-register that could cancel the NEXT
  /// pending alarm mid-delivery. The user's QA "only the first
  /// schedule played, all subsequent ones did not" was that exact
  /// race — the cancel-and-re-register was racing the OS's alarm
  /// delivery for the very next slot.
  ///
  /// If [forceRebuild] is true, the fingerprint check is bypassed —
  /// used on cold start / boot receiver replay when we can't be sure
  /// the AlarmManager table matches our last computed snapshot.
  Future<void> applySnapshot({
    required Iterable<PlaybackSchedule> schedules,
    required PlaylistRepository playlists,
    required bool active,
    bool forceRebuild = false,
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

    // ── STAGE 1: resolve the first playable clip for each schedule. This
    // is the only I/O-bound step; keep it OUTSIDE the fingerprint check
    // so a fingerprint-hit still returns quickly, but INSIDE the
    // projection loop so the fires we register point at real files.
    final resolvedClips = <String, ({String path, String title})>{};
    for (final schedule in enabled) {
      try {
        final list = await playlists.getClips(schedule.playlistId);
        for (final clip in list) {
          final path = clip.filePath;
          if (path.isEmpty) continue;
          if (!await File(path).exists()) continue;
          resolvedClips[schedule.id] = (
            path: path,
            title: clip.title.isNotEmpty ? clip.title : 'WhisperBack',
          );
          break;
        }
      } catch (e, st) {
        if (kDebugMode) {
          print(
              'NativeAlarmsBridge: resolve clip for ${schedule.id} failed: $e\n$st');
        }
      }
    }

    // ── STAGE 2: structural fingerprint. Only these fields change the
    // alarm TABLE structure: schedule id, days, start/end, interval,
    // playlist duration (drives `effectiveStepMinutes`), clip path
    // (drives what the receiver actually plays), and active state.
    // We intentionally do NOT include `lastFired` — the alarm table
    // is invariant across fires that only shift the projection by
    // sub-second drift.
    final structural =
        enabled.where((s) => resolvedClips.containsKey(s.id)).map((s) {
      final clip = resolvedClips[s.id]!;
      return [
        s.id,
        s.daysMask,
        s.startTime.hour * 60 + s.startTime.minute,
        (s.endTime?.hour ?? -1) * 60 + (s.endTime?.minute ?? 0),
        s.intervalMinutes,
        s.playlistDurationMs ~/ 1000,
        clip.path,
      ].join(':');
    }).toList()
          ..sort();
    final structuralFingerprint = '$active|${structural.join('|')}';

    // Refill window — if the last register was >12 h ago, force a
    // rebuild even if the fingerprint matches, so the tail of the
    // alarm table doesn't dry up on marathon (multi-day) sessions.
    final now = DateTime.now();
    final needsPeriodicRefill = _lastRegisteredAt == null ||
        now.difference(_lastRegisteredAt!) > const Duration(hours: 12);

    if (!forceRebuild &&
        !needsPeriodicRefill &&
        structuralFingerprint == _lastStructuralFingerprint) {
      if (kDebugMode) {
        print('NativeAlarmsBridge: structural fingerprint unchanged, '
            'alarm table left as-is (${enabled.length} schedules)');
      }
      return;
    }

    // ── STAGE 3: project fires. Only reached when the structure changed
    // OR the periodic refill window elapsed OR the caller forced it.
    final fires = <Map<String, Object?>>[];
    final lastFired = ScheduleLastFiredStore.instance;
    for (final schedule in enabled) {
      final clip = resolvedClips[schedule.id];
      if (clip == null) continue;
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
          'clipPath': clip.path,
          'clipTitle': clip.title,
          'playlistName': schedule.playlistName.isNotEmpty
              ? schedule.playlistName
              : 'WhisperBack',
          'fireEpochMs': next.millisecondsSinceEpoch,
        });
        added++;
        lastSlot = next;
        lastCompletion =
            next.add(Duration(milliseconds: schedule.playlistDurationMs));
        // Move the cursor PAST this slot so the helper returns the next one.
        cursor = next.add(const Duration(seconds: 1));
        if (fires.length >= _kMaxFiresTotal) break;
      }
      if (fires.length >= _kMaxFiresTotal) break;
    }
    fires.sort((a, b) =>
        (a['fireEpochMs']! as int).compareTo(b['fireEpochMs']! as int));
    final trimmed = fires.take(_kMaxFiresTotal).toList();
    final json = jsonEncode(trimmed);

    _lastStructuralFingerprint = structuralFingerprint;
    _lastRegisteredAt = now;
    try {
      final registered = await _channel.invokeMethod<int>('setSnapshot', {
        'snapshot': json,
        'active': active,
      });
      if (kDebugMode) {
        print('NativeAlarmsBridge: native registered $registered alarms '
            '(structural=${forceRebuild ? "force" : needsPeriodicRefill ? "refill" : "change"})');
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
    _lastStructuralFingerprint = null;
    _lastRegisteredAt = null;
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
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getPlaybackState');
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
