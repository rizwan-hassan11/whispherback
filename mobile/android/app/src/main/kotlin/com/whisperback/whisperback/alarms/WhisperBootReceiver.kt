package com.whisperback.whisperback.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Round 21 — re-arm WhisperBack alarms after device boot or app update.
 *
 * The `AlarmManager` table is cleared on every reboot, so without this
 * receiver the user would have to open the app once after every restart
 * for their schedules to start firing again. On Android 14+ "LockedBoot
 * Completed" delivers BEFORE the user unlocks, which is critical for
 * morning-prayer alarms.
 *
 * We hold the last-known snapshot JSON in SharedPreferences so we can
 * re-register without booting Flutter. If no snapshot is stored yet
 * (first run, fresh install) we silently no-op — the next time the
 * user opens the app, `setSnapshot()` will repopulate the table.
 */
class WhisperBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "WhisperBootRcv"
        const val SNAPSHOT_PREFS = "whisperback.alarms.snapshot"
        const val KEY_SNAPSHOT_JSON = "snapshot_json"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val action = intent?.action ?: return
            if (action != Intent.ACTION_BOOT_COMPLETED &&
                action != Intent.ACTION_MY_PACKAGE_REPLACED &&
                action != "android.intent.action.QUICKBOOT_POWERON" &&
                action != "android.intent.action.LOCKED_BOOT_COMPLETED"
            ) {
                return
            }
            Log.i(TAG, "boot action=$action; replaying snapshot")
            val prefs = context.getSharedPreferences(SNAPSHOT_PREFS, Context.MODE_PRIVATE)
            val json = prefs.getString(KEY_SNAPSHOT_JSON, null) ?: return
            if (json.isBlank()) return
            val count = WhisperAlarmScheduler.get(context).setSnapshot(json)
            Log.i(TAG, "re-armed $count alarms after $action")
        } catch (t: Throwable) {
            Log.e(TAG, "boot replay failed", t)
        }
    }
}
