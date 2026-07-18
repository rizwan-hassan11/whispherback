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
        // Round 24 — persist the full projected snapshot so the receiver
        // can re-arm the tail on every fire without needing Dart alive.
        // The prior Round-23 model relied on the coordinator refreshing
        // after each fire — if the app was killed between fires, the
        // tail eventually dried up. Storing the snapshot here lets
        // `WhisperAlarmReceiver.refillIfNeeded()` re-project the same
        // fires (minus already-past ones) with zero Dart involvement.
        const val KEY_SNAPSHOT_JSON = "snapshot_json_v2"
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
        // Round 24 — refill threshold. When the receiver processes a
        // fire and detects `remaining < REFILL_THRESHOLD`, it re-runs
        // `setSnapshot` from the persisted JSON with past-times
        // filtered out. This keeps the alarm table topped up
        // indefinitely even if Flutter has been killed by the OEM.
        const val REFILL_THRESHOLD = 8

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
     *
     * Round 24 — persists the snapshot JSON so the receiver can
     * re-project the tail on every fire without needing Dart alive.
     */
    fun setSnapshot(snapshotJson: String): Int {
        return try {
            cancelAllInternal()
            prefs.edit().putString(KEY_SNAPSHOT_JSON, snapshotJson).apply()
            val registered = registerFromJson(snapshotJson)
            Log.i(TAG, "snapshot applied: registered=$registered fires")
            registered
        } catch (t: Throwable) {
            Log.e(TAG, "setSnapshot failed", t)
            0
        }
    }

    /**
     * Round 24 — count of alarms currently pending.
     *
     * NOTE: this counts REGISTERED ids, not truly-pending ids. After a
     * fire is delivered and consumed by the OS, the id remains in
     * `KEY_REQ_IDS` until the next `setSnapshot`. Use [futurePendingCount]
     * for a time-accurate pending count.
     */
    fun pendingCount(): Int {
        return try {
            val raw = prefs.getString(KEY_REQ_IDS, null) ?: return 0
            JSONArray(raw).length()
        } catch (t: Throwable) {
            Log.e(TAG, "pendingCount failed", t)
            0
        }
    }

    /**
     * Round 24 — time-accurate count of alarms still in the future.
     * Uses the persisted snapshot JSON to filter by `fireEpochMs > now`.
     * This is what the receiver uses to decide whether to refill.
     */
    fun futurePendingCount(): Int {
        return try {
            val json = prefs.getString(KEY_SNAPSHOT_JSON, null) ?: return 0
            val fires = parseFires(json)
            val now = System.currentTimeMillis()
            fires.count { it.fireEpochMs > now }
        } catch (t: Throwable) {
            Log.e(TAG, "futurePendingCount failed", t)
            0
        }
    }

    /**
     * Round 24 — receiver-triggered refill.
     *
     * Called from `WhisperAlarmReceiver` on every fire. If the tail has
     * dried up (< [REFILL_THRESHOLD] future fires remaining in the
     * persisted snapshot), we EXTEND the snapshot by projecting more
     * fires forward. Since the receiver can't invoke the Dart
     * projection, we use a native fallback: the last fire in the
     * snapshot plus a fixed interval. It's approximate but keeps the
     * chain alive until Flutter next runs and produces a real
     * projection.
     *
     * This method is called on every alarm fire and MUST be cheap on
     * the common path (returns 0 immediately if there's nothing to do).
     */
    fun refillIfNeeded(): Int {
        return try {
            val remaining = futurePendingCount()
            if (remaining >= REFILL_THRESHOLD) {
                return 0
            }
            val json = prefs.getString(KEY_SNAPSHOT_JSON, null)
            if (json.isNullOrBlank()) {
                Log.w(TAG, "refillIfNeeded: no snapshot to replay (remaining=$remaining)")
                return 0
            }
            // Extend the persisted snapshot by extrapolating from the
            // last known fire (per schedule) using the observed inter-
            // fire delta. This is best-effort — Flutter will overwrite
            // it with a real projection next time it's alive — but it
            // keeps the alarm chain firing indefinitely when the app
            // has been reaped by the OEM.
            val extended = extendSnapshot(json, targetSize = MAX_ALARMS / 2) ?: json
            prefs.edit().putString(KEY_SNAPSHOT_JSON, extended).apply()
            val registered = registerFromJson(extended)
            Log.i(TAG, "refill applied: registered=$registered (was $remaining, extended=${extended !== json})")
            registered
        } catch (t: Throwable) {
            Log.e(TAG, "refillIfNeeded failed", t)
            0
        }
    }

    /**
     * Round 24 — best-effort native extension of a snapshot when Dart
     * isn't around to project new fires. Groups fires by scheduleId,
     * observes the median inter-fire delta, and appends synthetic
     * fires forward until each schedule has at least [targetSize]
     * future entries.
     *
     * Returns the extended JSON, or null if extension wasn't possible
     * (e.g. we only have one fire per schedule, so no delta to
     * observe).
     */
    private fun extendSnapshot(json: String, targetSize: Int): String? {
        return try {
            val fires = parseFires(json).toMutableList()
            if (fires.isEmpty()) return null
            val now = System.currentTimeMillis()

            // Group by scheduleId, compute the median inter-fire delta.
            val grouped = fires.groupBy { it.scheduleId }
            val extras = mutableListOf<Fire>()
            for ((scheduleId, list) in grouped) {
                if (list.size < 2) continue
                val sorted = list.sortedBy { it.fireEpochMs }
                val deltas = mutableListOf<Long>()
                for (i in 1 until sorted.size) {
                    deltas.add(sorted[i].fireEpochMs - sorted[i - 1].fireEpochMs)
                }
                val medianDelta = deltas.sorted()[deltas.size / 2]
                if (medianDelta <= 0L) continue
                val last = sorted.last()
                val futureCount = list.count { it.fireEpochMs > now }
                var next = last.fireEpochMs + medianDelta
                var added = 0
                while (futureCount + added < targetSize) {
                    if (added > MAX_ALARMS) break
                    extras.add(
                        Fire(
                            scheduleId = scheduleId,
                            clipPath = last.clipPath,
                            clipTitle = last.clipTitle,
                            playlistName = last.playlistName,
                            fireEpochMs = next,
                            clipQueueJson = last.clipQueueJson,
                        )
                    )
                    added++
                    next += medianDelta
                }
                Log.d(TAG, "extendSnapshot: scheduleId=$scheduleId added=$added medianDelta=${medianDelta}ms")
            }
            if (extras.isEmpty()) return null
            fires.addAll(extras)
            // Rebuild JSON in fireEpoch order.
            fires.sortBy { it.fireEpochMs }
            val arr = JSONArray()
            for (f in fires) {
                val obj = JSONObject()
                    .put("scheduleId", f.scheduleId)
                    .put("clipPath", f.clipPath)
                    .put("clipTitle", f.clipTitle)
                    .put("playlistName", f.playlistName)
                    .put("fireEpochMs", f.fireEpochMs)
                if (f.clipQueueJson.isNotBlank()) {
                    obj.put("clipQueueJson", f.clipQueueJson)
                }
                arr.put(obj)
            }
            arr.toString()
        } catch (t: Throwable) {
            Log.e(TAG, "extendSnapshot failed", t)
            null
        }
    }

    private fun registerFromJson(json: String): Int {
        cancelAllInternal()
        val fires = parseFires(json)
        val now = System.currentTimeMillis()
        var registered = 0
        val ids = mutableListOf<Int>()
        for (fire in fires) {
            if (registered >= MAX_ALARMS) break
            // Round 29: allow fires up to 2 minutes in the past so a
            // grace-window "now" slot still gets a PendingIntent (the OS
            // delivers it immediately). Previously `<= now` silently
            // dropped the current slot when Active was toggled mid-minute.
            if (fire.fireEpochMs < now - 2 * 60 * 1000L) continue
            val requestId = REQUEST_ID_BASE + registered
            val ok = registerOne(requestId, fire)
            if (ok) {
                ids.add(requestId)
                registered++
            }
        }
        prefs.edit().putString(KEY_REQ_IDS, JSONArray(ids).toString()).apply()
        return registered
    }

    /** Cancel every alarm we currently track. */
    fun cancelAll() {
        try {
            cancelAllInternal()
            prefs.edit()
                .remove(KEY_REQ_IDS)
                .remove(KEY_SNAPSHOT_JSON)
                .apply()
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
            putExtra(WhisperAlarmReceiver.EXTRA_CLIP_QUEUE_JSON, fire.clipQueueJson)
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
        val clipQueueJson: String = "",
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
            val clipQueueJson = obj.optString("clipQueueJson", "")
            val fireMs = obj.optLong("fireEpochMs", 0L)
            if (fireMs <= 0L) return null
            Fire(scheduleId, clipPath, clipTitle, playlistName, fireMs, clipQueueJson)
        } catch (t: Throwable) {
            Log.e(TAG, "parseFire failed", t)
            null
        }
    }
}
