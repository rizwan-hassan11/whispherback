package com.whisperback.whisperback.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Round 21 — alarm-clock model for scheduled audio.
 *
 * `WhisperAlarmScheduler` registers exact `AlarmManager.setAlarmClock`
 * PendingIntents pointed at this receiver. When the alarm fires, the OS
 * delivers the intent here (even when the app is dead and the device is in
 * Doze, because alarm-clock alarms are Doze-exempt and grant a temporary
 * background FG-start whitelist).
 *
 * We immediately start `WhisperPlaybackService` (foreground service typed
 * `mediaPlayback`) and pass the clip path + display title via intent extras.
 * The service plays the clip via `MediaPlayer` from inside its own
 * lifecycle so the audio survives this receiver returning.
 *
 * EVERY action in here is wrapped in try/catch so a single failed alarm
 * never surfaces as the user-visible "WhisperBack keeps crashing" dialog.
 */
class WhisperAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "WhisperAlarmRcv"
        const val ACTION_FIRE_ALARM = "com.whisperback.alarms.FIRE"
        const val EXTRA_SCHEDULE_ID = "schedule_id"
        const val EXTRA_CLIP_PATH = "clip_path"
        const val EXTRA_CLIP_TITLE = "clip_title"
        const val EXTRA_PLAYLIST_NAME = "playlist_name"
        const val EXTRA_SLOT_EPOCH_MS = "slot_epoch_ms"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        try {
            if (intent?.action != ACTION_FIRE_ALARM) {
                Log.w(TAG, "ignoring intent with action ${intent?.action}")
                return
            }

            val clipPath = intent.getStringExtra(EXTRA_CLIP_PATH)
            val scheduleId = intent.getStringExtra(EXTRA_SCHEDULE_ID)
            val clipTitle = intent.getStringExtra(EXTRA_CLIP_TITLE) ?: "WhisperBack"
            val playlistName = intent.getStringExtra(EXTRA_PLAYLIST_NAME) ?: "Scheduled whisper"
            val slotEpochMs = intent.getLongExtra(EXTRA_SLOT_EPOCH_MS, 0L)
            Log.i(
                TAG,
                "alarm fired: scheduleId=$scheduleId clipPath=$clipPath title=$clipTitle slot=$slotEpochMs",
            )

            if (clipPath.isNullOrBlank()) {
                Log.w(TAG, "no clip path supplied; dropping alarm")
                return
            }

            // Tight grace window — if this fire is more than 5 minutes
            // late we silently skip. Prevents the "alarm I missed an
            // hour ago fired the moment I unplugged" surprise.
            if (slotEpochMs > 0) {
                val deltaMs = System.currentTimeMillis() - slotEpochMs
                if (deltaMs > 5 * 60 * 1000L) {
                    Log.w(TAG, "alarm is ${deltaMs}ms late, skipping")
                    return
                }
            }

            // Hand off to the typed FG service. We use
            // `startForegroundService` (Android 8+) which gives the service
            // ~10 s to call startForeground() — well inside our budget.
            val serviceIntent = Intent(context, WhisperPlaybackService::class.java).apply {
                action = WhisperPlaybackService.ACTION_PLAY_CLIP
                putExtra(WhisperPlaybackService.EXTRA_CLIP_PATH, clipPath)
                putExtra(WhisperPlaybackService.EXTRA_CLIP_TITLE, clipTitle)
                putExtra(WhisperPlaybackService.EXTRA_PLAYLIST_NAME, playlistName)
                putExtra(WhisperPlaybackService.EXTRA_SCHEDULE_ID, scheduleId)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (t: Throwable) {
                // ForegroundServiceStartNotAllowedException can land here
                // if the OS decided this alarm doesn't count as a user
                // wake-up (e.g. duplicate firing during a Doze unbox).
                Log.e(TAG, "startForegroundService failed", t)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed (swallowed)", t)
        }
    }
}
