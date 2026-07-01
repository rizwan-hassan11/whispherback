package com.whisperback.whisperback.alarms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Round 21 — registers `AlarmManager.setAlarmClock` PendingIntents for
 * every upcoming scheduled-audio slot the Dart side computes.
 *
 * Why `setAlarmClock`?
 *   • Doze-exempt (the device leaves Doze briefly before the alarm fires).
 *   • Granted a temporary background-FG-start whitelist on Android 12+, so
 *     `WhisperAlarmReceiver` can lawfully start a `mediaPlayback` FG
 *     service.
 *   • Highest reliability class on aggressive OEMs (Xiaomi/Vivo/OnePlus).
 *
 * Why not `WorkManager` or `setExactAndAllowWhileIdle`?
 *   • WorkManager has a 10-minute minimum and is deferred during Doze.
 *   • `setExactAndAllowWhileIdle` is throttled to 9-minute minimums on
 *     Android 12+ for non-alarm-clock alarms.
 *
 * Snapshot protocol:
 *   The Dart side passes us a JSON array of fires:
 *     [{"scheduleId":"…","clipPath":"…","clipTitle":"…",
 *       "playlistName":"…","fireEpochMs":1234567890}, …]
 *
 *   We:
 *     1. Cancel every previously-registered alarm (we track ids in
 *        SharedPreferences so cancellation survives process death).
 *     2. Register a fresh `setAlarmClock` per fire, capped at MAX_ALARMS
 *        (192 — Android's per-app alarm cap is 500, but we keep a safety
 *        margin for `flutter_local_notifications` and prayer alarms).
 *
 * This keeps the OS scheduling table in lockstep with the user's
 * intent — every save/toggle from Dart triggers `setSnapshot()` which
 * atomically rebuilds the table.
 */
class WhisperAlarmScheduler private constructor(private val appContext: Context) {
    companion object {
        private const val TAG = "WhisperAlarmSched"
        private const val PREFS = "whisperback.alarms"
        private const val KEY_REQ_IDS = "registered_request_ids"
        // Base request-id offset — keeps us clear of any other PendingIntent
        // request-id space the app uses.
        private const val REQUEST_ID_BASE = 0x7E_00_00_00.toInt()
        // Round 23 — bumped from 192 to 400 so a 5-minute-interval
        // schedule can pre-register a full 33 hours of alarms while
        // still leaving headroom (Android's per-app cap is 500) for
        // `flutter_local_notifications` and prayer alarms. The QA
        // report "later schedules stopped working" was the tail of
        // the alarm table drying up: after the first ~4 hours of
        // fires (48 per-schedule cap × ~5-min interval) the table
        // was empty and no more clips would play until the user
        // re-opened the app.
        private const val MAX_ALARMS = 400

        @Volatile private var instance: WhisperAlarmScheduler? = null

        fun get(context: Context): WhisperAlarmScheduler {
            val existing = instance
            if (existing != null) return existing
            synchronized(this) {
                val again = instance
                if (again != null) return again
                val fresh = WhisperAlarmScheduler(context.applicationContext)
                instance = fresh
                return fresh
            }
        }
    }

    private val alarmManager: AlarmManager? by lazy {
        try {
            appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        } catch (t: Throwable) {
            Log.e(TAG, "AlarmManager lookup failed", t)
            null
        }
    }

    private val prefs: SharedPreferences by lazy {
        appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    /**
     * Atomically replace the registered alarm table with `snapshotJson`.
     * Safe to call from the main thread.
     */
    fun setSnapshot(snapshotJson: String): Int {
        return try {
            cancelAllInternal()
            val fires = parseFires(snapshotJson)
            val now = System.currentTimeMillis()
            var registered = 0
            val ids = mutableListOf<Int>()
            for (fire in fires) {
                if (registered >= MAX_ALARMS) break
                if (fire.fireEpochMs <= now) continue
                val requestId = REQUEST_ID_BASE + registered
                val ok = registerOne(requestId, fire)
                if (ok) {
                    ids.add(requestId)
                    registered++
                }
            }
            prefs.edit().putString(KEY_REQ_IDS, JSONArray(ids).toString()).apply()
            Log.i(TAG, "snapshot applied: registered=$registered fires")
            registered
        } catch (t: Throwable) {
            Log.e(TAG, "setSnapshot failed", t)
            0
        }
    }

    /** Cancel every alarm we currently track. */
    fun cancelAll() {
        try {
            cancelAllInternal()
            prefs.edit().remove(KEY_REQ_IDS).apply()
        } catch (t: Throwable) {
            Log.e(TAG, "cancelAll failed", t)
        }
    }

    private fun cancelAllInternal() {
        val mgr = alarmManager ?: return
        val raw = prefs.getString(KEY_REQ_IDS, null) ?: return
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val rid = arr.optInt(i, Int.MIN_VALUE)
                if (rid == Int.MIN_VALUE) continue
                try {
                    val pi = PendingIntent.getBroadcast(
                        appContext,
                        rid,
                        templateIntent(),
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                    )
                    if (pi != null) {
                        mgr.cancel(pi)
                        pi.cancel()
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "cancel rid=$rid failed", t)
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "cancelAllInternal parse failed", t)
        }
    }

    private fun registerOne(requestId: Int, fire: Fire): Boolean {
        val mgr = alarmManager ?: return false
        // Android 12+ require canScheduleExactAlarms() before
        // setAlarmClock(). If denied we fall back to
        // setExactAndAllowWhileIdle (less reliable but still scheduled).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!mgr.canScheduleExactAlarms()) {
                Log.w(TAG, "exact alarms denied; falling back to allowWhileIdle")
                return registerAllowWhileIdle(requestId, fire)
            }
        }
        return try {
            val pi = buildPendingIntent(requestId, fire)
            val showIntent = openAppPendingIntent(requestId)
            val info = AlarmManager.AlarmClockInfo(fire.fireEpochMs, showIntent)
            mgr.setAlarmClock(info, pi)
            true
        } catch (sec: SecurityException) {
            Log.e(TAG, "setAlarmClock SecurityException; trying allowWhileIdle", sec)
            registerAllowWhileIdle(requestId, fire)
        } catch (t: Throwable) {
            Log.e(TAG, "setAlarmClock failed", t)
            false
        }
    }

    private fun registerAllowWhileIdle(requestId: Int, fire: Fire): Boolean {
        val mgr = alarmManager ?: return false
        return try {
            val pi = buildPendingIntent(requestId, fire)
            mgr.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire.fireEpochMs, pi)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "setExactAndAllowWhileIdle failed", t)
            false
        }
    }

    private fun buildPendingIntent(requestId: Int, fire: Fire): PendingIntent {
        val intent = templateIntent().apply {
            putExtra(WhisperAlarmReceiver.EXTRA_SCHEDULE_ID, fire.scheduleId)
            putExtra(WhisperAlarmReceiver.EXTRA_CLIP_PATH, fire.clipPath)
            putExtra(WhisperAlarmReceiver.EXTRA_CLIP_TITLE, fire.clipTitle)
            putExtra(WhisperAlarmReceiver.EXTRA_PLAYLIST_NAME, fire.playlistName)
            putExtra(WhisperAlarmReceiver.EXTRA_SLOT_EPOCH_MS, fire.fireEpochMs)
        }
        return PendingIntent.getBroadcast(
            appContext,
            requestId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openAppPendingIntent(requestId: Int): PendingIntent {
        val intent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
            ?: Intent()
        return PendingIntent.getActivity(
            appContext,
            requestId xor 0x55_55_55_55.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun templateIntent(): Intent =
        Intent(appContext, WhisperAlarmReceiver::class.java).apply {
            action = WhisperAlarmReceiver.ACTION_FIRE_ALARM
        }

    private data class Fire(
        val scheduleId: String,
        val clipPath: String,
        val clipTitle: String,
        val playlistName: String,
        val fireEpochMs: Long,
    )

    private fun parseFires(json: String): List<Fire> {
        val out = mutableListOf<Fire>()
        if (json.isBlank()) return out
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val fire = parseFire(obj) ?: continue
                out.add(fire)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "parseFires failed", t)
        }
        return out
    }

    private fun parseFire(obj: JSONObject): Fire? {
        return try {
            val scheduleId = obj.optString("scheduleId").takeIf { it.isNotBlank() } ?: return null
            val clipPath = obj.optString("clipPath").takeIf { it.isNotBlank() } ?: return null
            val clipTitle = obj.optString("clipTitle").ifBlank { "WhisperBack" }
            val playlistName = obj.optString("playlistName").ifBlank { "Scheduled whisper" }
            val fireMs = obj.optLong("fireEpochMs", 0L)
            if (fireMs <= 0L) return null
            Fire(scheduleId, clipPath, clipTitle, playlistName, fireMs)
        } catch (t: Throwable) {
            Log.e(TAG, "parseFire failed", t)
            null
        }
    }
}
