package com.whisperback.whisperback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Native Android foreground service that owns the WhisperBack process lifecycle
 * independently of `audio_service` and `just_audio`. Started when the user toggles
 * Active ON via `WhisperKeepAliveBridge` (Flutter -> native MethodChannel). Stays
 * alive across activity destruction so the schedule engine in the Dart isolate
 * keeps ticking and scheduled fires can play.
 *
 * Why this is necessary:
 *   The `audio_service` plugin's foreground service is owned by the plugin and
 *   tied to the MediaSession `playing` state. On Samsung One UI 6 / Vivo
 *   Funtouch 14 / Xiaomi MIUI 14, even a `playing: true` MediaSession with a
 *   genuinely-audible (volume 0.001) silence loop can be reaped by the OS
 *   shortly after the activity is destroyed. Without an OS-recognised "this
 *   process MUST stay alive" signal, schedules silently die a few minutes
 *   after the user closes the app.
 *
 *   By running OUR OWN foreground service with a high-importance notification
 *   and a partial wake lock, we put the process into the "user-visible
 *   foreground service" priority bucket that even aggressive OEM battery
 *   managers respect (without requiring battery-exemption grant).
 *
 *   This service does NOT play audio. It's purely a process-keep-alive that
 *   complements `audio_service` (which handles MediaSession + lock-screen
 *   controls + the actual audio output).
 */
class WhisperKeepAliveService : Service() {

    companion object {
        private const val TAG = "WhisperKeepAlive"
        private const val NOTIFICATION_ID = 0x57424B // 'WBK'
        private const val CHANNEL_ID = "whisperback_keep_alive"
        private const val CHANNEL_NAME = "WhisperBack background"
        private const val ACTION_START = "com.whisperback.START_KEEP_ALIVE"
        private const val ACTION_STOP = "com.whisperback.STOP_KEEP_ALIVE"
        private const val WAKE_LOCK_TAG = "WhisperBack::KeepAliveWakeLock"
        private const val HEARTBEAT_INTERVAL_MS = 60_000L

        fun start(context: Context) {
            val intent = Intent(context, WhisperKeepAliveService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "start: failed to start service", t)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, WhisperKeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (t: Throwable) {
                Log.w(TAG, "stop: failed to stop service", t)
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var heartbeatHandler: android.os.Handler? = null
    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            // Round 20: every minute, re-acquire the wake lock and
            // re-post the FG notification. Some OEM battery managers
            // (Samsung One UI 6, Vivo Funtouch 14, Xiaomi MIUI 14)
            // silently downgrade the FG status of long-running
            // services that "look idle". Re-asserting startForeground
            // forces the OS scheduler to keep us in the "user-visible
            // foreground" bucket.
            try {
                startForegroundCompat()
            } catch (t: Throwable) {
                Log.w(TAG, "heartbeat: startForegroundCompat failed", t)
            }
            try {
                acquireWakeLock()
            } catch (t: Throwable) {
                Log.w(TAG, "heartbeat: acquireWakeLock failed", t)
            }
            heartbeatHandler?.postDelayed(this, HEARTBEAT_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        // On Android 8+ we MUST call startForeground within ~5 seconds of
        // startForegroundService, even if onStartCommand hasn't run yet —
        // post the FG notification immediately to avoid the OS killing us
        // for a `ForegroundServiceDidNotStartInTimeException`.
        startForegroundCompat()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopHeartbeat()
                releaseWakeLock()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                // ACTION_START or null (system-restart): post the FG
                // notification (idempotent) and acquire the wake lock.
                startForegroundCompat()
                acquireWakeLock()
                startHeartbeat()
            }
        }
        // START_STICKY so the OS re-creates the service if it's killed.
        return START_STICKY
    }

    override fun onDestroy() {
        stopHeartbeat()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startHeartbeat() {
        if (heartbeatHandler != null) return
        heartbeatHandler = android.os.Handler(mainLooper)
        heartbeatHandler?.postDelayed(heartbeatRunnable, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopHeartbeat() {
        heartbeatHandler?.removeCallbacks(heartbeatRunnable)
        heartbeatHandler = null
    }

    /**
     * `stopWithTask=false` on the manifest entry plus this empty override
     * ensures the service stays alive when the user swipes the task. The
     * default would call `stopSelf` here.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        // Intentionally a no-op so background scheduling continues after
        // the user swipes the activity away. Do NOT call super or stopSelf.
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+: explicit foreground service type required.
                // We use `SPECIAL_USE` because we are not playing audio
                // here — `audio_service` owns the mediaPlayback FG type
                // and the OS rejects two services with the same type.
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "startForegroundCompat: failed", t)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent()
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingFlags,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("WhisperBack is active")
            .setContentText("Scheduled whispers will play in the background.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps WhisperBack running in the background so " +
                "scheduled whispers can play even when the app is closed."
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val newLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG,
            )
            newLock.setReferenceCounted(false)
            // No timeout: we release explicitly when the user turns Active OFF.
            newLock.acquire()
            wakeLock = newLock
        } catch (t: Throwable) {
            Log.w(TAG, "acquireWakeLock: failed", t)
        }
    }

    private fun releaseWakeLock() {
        try {
            val held = wakeLock
            if (held != null && held.isHeld) {
                held.release()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "releaseWakeLock: failed", t)
        } finally {
            wakeLock = null
        }
    }
}
