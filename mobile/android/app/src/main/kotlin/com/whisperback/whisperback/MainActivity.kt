package com.whisperback.whisperback

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import com.whisperback.whisperback.alarms.WhisperAlarmScheduler
import com.whisperback.whisperback.alarms.WhisperBootReceiver
import com.whisperback.whisperback.alarms.WhisperPlaybackService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val KEEP_ALIVE_CHANNEL = "com.whisperback.keep_alive"
        private const val ALARM_CHANNEL = "com.whisperback.alarms"
        // Round 24 — native duration probe used by ClipRepository.
        // `just_audio`'s Dart-side probe binds the file to the shared
        // AudioSession which either drops audio focus (silent play) or
        // returns null on Samsung / Vivo OEMs. MediaMetadataRetriever
        // reads the container header directly with no MediaSession.
        private const val CLIP_METADATA_CHANNEL = "com.whisperback.clip_metadata"
    }

    private var alarmChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15/16 edge-to-edge: let Flutter handle system bar insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        // Round 22 — drop the Dart-side listener so the service doesn't try
        // to call back into a dead Flutter engine after the activity dies.
        // (The mirrored-prefs path means Dart still picks up state on
        // re-launch.)
        WhisperPlaybackService.stateListener = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEEP_ALIVE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    WhisperKeepAliveService.start(applicationContext)
                    result.success(null)
                }
                "stop" -> {
                    WhisperKeepAliveService.stop(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Round 21/22 — native alarm-clock scheduler + scheduled-playback
        // control surface. Dart computes the upcoming-fires snapshot from
        // the user's schedules and pushes it here on every save / toggle /
        // app resume. We mirror it into SharedPreferences so the boot
        // receiver can re-arm without booting Flutter.
        //
        // Round 22 adds:
        //   • `pauseNative`, `resumeNative`, `stopNative` — Dart can pause
        //     / resume / stop the scheduled playback service from the
        //     mini-player and modal so the user has the same control over
        //     a scheduled clip that they have over a manual one.
        //   • `setVolume` — pushes the user's volume slider value
        //     (0.0–1.0) into SharedPreferences; the next playClip honors
        //     it. The QA report "scheduled audio plays at full volume" is
        //     primarily fixed by switching the audio attributes to media
        //     usage, but the slider value is the second half of the fix.
        //   • `getPlaybackState` — Dart polls this on resume so the
        //     mini-player can show a scheduled clip that started while
        //     the app was closed.
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_CHANNEL,
        )
        alarmChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setSnapshot" -> {
                        val args = call.arguments
                        val json: String
                        val active: Boolean
                        if (args is Map<*, *>) {
                            json = (args["snapshot"] as? String) ?: "[]"
                            active = (args["active"] as? Boolean) ?: true
                        } else {
                            json = (args as? String) ?: "[]"
                            active = true
                        }
                        applicationContext
                            .getSharedPreferences(WhisperBootReceiver.SNAPSHOT_PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putString(WhisperBootReceiver.KEY_SNAPSHOT_JSON, json)
                            .putBoolean("is_active", active)
                            .apply()
                        val registered =
                            WhisperAlarmScheduler.get(applicationContext).setSnapshot(json)
                        result.success(registered)
                    }
                    "cancelAll" -> {
                        applicationContext
                            .getSharedPreferences(WhisperBootReceiver.SNAPSHOT_PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .remove(WhisperBootReceiver.KEY_SNAPSHOT_JSON)
                            .putBoolean("is_active", false)
                            .apply()
                        WhisperAlarmScheduler.get(applicationContext).cancelAll()
                        // Also tear down any in-flight scheduled playback.
                        sendCommandToService(WhisperPlaybackService.ACTION_STOP_NOW)
                        result.success(null)
                    }
                    "pauseNative" -> {
                        sendCommandToService(WhisperPlaybackService.ACTION_PAUSE)
                        result.success(null)
                    }
                    "resumeNative" -> {
                        sendCommandToService(WhisperPlaybackService.ACTION_RESUME)
                        result.success(null)
                    }
                    "stopNative" -> {
                        sendCommandToService(WhisperPlaybackService.ACTION_STOP_NOW)
                        result.success(null)
                    }
                    "setVolume" -> {
                        val raw = call.arguments
                        val vol = when (raw) {
                            is Double -> raw.toFloat()
                            is Float -> raw
                            is Int -> raw.toFloat()
                            else -> 1.0f
                        }.coerceIn(0f, 1f)
                        applicationContext
                            .getSharedPreferences(WhisperPlaybackService.STATE_PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putFloat(WhisperPlaybackService.KEY_VOLUME, vol)
                            .apply()
                        result.success(null)
                    }
                    "getPlaybackState" -> {
                        val prefs = applicationContext.getSharedPreferences(
                            WhisperPlaybackService.STATE_PREFS,
                            Context.MODE_PRIVATE,
                        )
                        val map = mapOf(
                            "state" to (prefs.getString(WhisperPlaybackService.KEY_STATE, WhisperPlaybackService.STATE_IDLE) ?: WhisperPlaybackService.STATE_IDLE),
                            "clipPath" to prefs.getString(WhisperPlaybackService.KEY_CURRENT_PATH, null),
                            "clipTitle" to prefs.getString(WhisperPlaybackService.KEY_CURRENT_TITLE, null),
                            "playlistName" to prefs.getString(WhisperPlaybackService.KEY_CURRENT_PLAYLIST, null),
                            "scheduleId" to prefs.getString(WhisperPlaybackService.KEY_CURRENT_SCHEDULE_ID, null),
                            "durationMs" to prefs.getLong(WhisperPlaybackService.KEY_DURATION_MS, 0L),
                            "positionMs" to prefs.getLong(WhisperPlaybackService.KEY_POSITION_MS, 0L),
                        )
                        result.success(map)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("alarm_error", t.message, null)
            }
        }

        // Round 22 — register a Dart-side listener so the playback service
        // can push state changes (e.g. "I started playing the 7:00 PM
        // clip", "user pressed Pause in the notification shade") into
        // Flutter. This is what makes the mini-player light up the moment
        // the scheduled clip starts.
        WhisperPlaybackService.stateListener =
            lambda@{ state, clipPath, clipTitle, playlistName, scheduleId, durationMs, positionMs ->
                try {
                    val ch = alarmChannel ?: return@lambda
                    // MUST hop to the main thread — invokeMethod is not safe
                    // off-thread. Posting via Handler ensures we don't
                    // crash if the listener fires from MediaPlayer's
                    // worker thread.
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        try {
                            ch.invokeMethod(
                                "onScheduledPlaybackState",
                                mapOf(
                                    "state" to state,
                                    "clipPath" to clipPath,
                                    "clipTitle" to clipTitle,
                                    "playlistName" to playlistName,
                                    "scheduleId" to scheduleId,
                                    "durationMs" to durationMs,
                                    "positionMs" to positionMs,
                                ),
                            )
                        } catch (_: Throwable) {
                            // Channel might be torn down mid-callback.
                        }
                    }
                } catch (_: Throwable) {
                    // Defensive — never let a state callback crash playback.
                }
            }

        // Round 24 — native clip-duration probe. See ClipMetadataProbe.kt
        // for the "why not just_audio" rationale. Called by the Dart
        // side's `ClipRepository.backfillDuration` as its primary path;
        // falls back to `just_audio` only if this channel is missing.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CLIP_METADATA_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readDurationMs" -> {
                        val path = when (val raw = call.arguments) {
                            is String -> raw
                            is Map<*, *> -> (raw["filePath"] as? String) ?: ""
                            else -> ""
                        }
                        val duration = ClipMetadataProbe.readDurationMs(applicationContext, path)
                        result.success(duration)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("clip_metadata_error", t.message, null)
            }
        }
    }

    private fun sendCommandToService(action: String) {
        val intent = Intent(applicationContext, WhisperPlaybackService::class.java).apply {
            this.action = action
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(intent)
            } else {
                applicationContext.startService(intent)
            }
        } catch (_: Throwable) {
            // ForegroundServiceStartNotAllowedException can hit on Android
            // 12+ if the service was killed and we have no FG grant. The
            // mirrored-prefs state + the next alarm cycle will recover.
        }
    }
}
