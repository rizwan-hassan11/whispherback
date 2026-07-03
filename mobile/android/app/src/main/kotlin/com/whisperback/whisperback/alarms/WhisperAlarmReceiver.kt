package com.whisperback.whisperback.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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

        // Round 23 — de-duplication window. On some OEMs (Vivo, Realme)
        // the OS occasionally delivers the same alarm PendingIntent twice
        // within a few seconds (usually when the device wakes from Doze
        // and the alarm has been queued during a maintenance window).
        // Without dedup, the QA report "clip plays twice back-to-back on
        // some Android 12 phones" reproduced. 60 s is safely below the
        // shortest supported interval (1 minute) so we never dedup two
        // genuine successive slots.
        private const val DEDUP_WINDOW_MS = 60_000L
        private const val DEDUP_PREFS = "whisperback.alarms.dedup"
        private const val DEDUP_KEY_PREFIX = "last_fire_"
    }

    private fun dedupPrefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(DEDUP_PREFS, Context.MODE_PRIVATE)

    private fun isDuplicateFire(
        context: Context,
        scheduleId: String,
        slotEpochMs: Long,
    ): Boolean {
        if (slotEpochMs <= 0L) return false
        return try {
            val prefs = dedupPrefs(context)
            val key = "$DEDUP_KEY_PREFIX$scheduleId"
            val lastSlot = prefs.getLong(key, 0L)
            val delta = Math.abs(slotEpochMs - lastSlot)
            if (delta in 0..DEDUP_WINDOW_MS && lastSlot != 0L) {
                Log.w(TAG, "duplicate fire for $scheduleId slot=$slotEpochMs (last=$lastSlot dt=$delta ms)")
                true
            } else {
                prefs.edit().putLong(key, slotEpochMs).apply()
                false
            }
        } catch (t: Throwable) {
            Log.e(TAG, "dedup check failed (allowing fire)", t)
            false
        }
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

            // Round 23 — refuse a duplicate delivery of the same slot
            // within a 60 s window. On some OEMs the OS re-delivers a
            // queued alarm when the device leaves Doze, which without
            // this guard reproduced the QA report "clip plays twice
            // back to back".
            if (!scheduleId.isNullOrBlank() && isDuplicateFire(context, scheduleId, slotEpochMs)) {
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

            // Round 24 — after handing off to the FG service, top up the
            // alarm table if we're running low. This is what keeps the
            // chain firing indefinitely even when the app process has
            // been reaped: we DON'T rely on Dart being alive to project
            // the next 288 fires. `refillIfNeeded()` is cheap on the
            // common path (returns 0 immediately if the tail is still
            // healthy).
            try {
                WhisperAlarmScheduler.get(context).refillIfNeeded()
            } catch (t: Throwable) {
                Log.e(TAG, "refillIfNeeded from onReceive failed", t)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed (swallowed)", t)
        }
    }
}
