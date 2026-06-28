package com.whisperback.whisperback

import android.content.Context
import android.os.Bundle
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import com.whisperback.whisperback.alarms.WhisperAlarmScheduler
import com.whisperback.whisperback.alarms.WhisperBootReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val KEEP_ALIVE_CHANNEL = "com.whisperback.keep_alive"
        private const val ALARM_CHANNEL = "com.whisperback.alarms"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15/16 edge-to-edge: let Flutter handle system bar insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
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

        // Round 21 — native alarm-clock scheduler. Dart computes the
        // upcoming-fires snapshot from the user's schedules and pushes it
        // here on every save / toggle / app resume. We mirror it into
        // SharedPreferences so the boot receiver can re-arm without
        // booting Flutter.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_CHANNEL,
        ).setMethodCallHandler { call, result ->
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
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("alarm_error", t.message, null)
            }
        }
    }
}
