package com.whisperback.whisperback.alarms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import com.whisperback.whisperback.MainActivity
import com.whisperback.whisperback.R
import java.io.File

/**
 * Round 21 — typed `mediaPlayback` foreground service that owns the
 * scheduled-audio MediaPlayer.
 *
 * Why this exists (vs Round 20's Dart background isolate):
 *   • Android 14+ rejects audio playback from a background-only context
 *     (no foreground service → no audio focus → silence). Our prior
 *     `just_audio` background-isolate path met all of those criteria,
 *     hence "notification shows the slot but nothing plays".
 *   • A typed `mediaPlayback` FG service is the standard
 *     Android way to play audio while the app is closed. The user-visible
 *     foreground notification it posts also keeps the OS from killing it
 *     mid-clip.
 *   • The service is started by `WhisperAlarmReceiver` which the OS
 *     delivers via `setAlarmClock` PendingIntents — Doze-exempt, with a
 *     temporary background-FG-start whitelist that lasts long enough for
 *     us to call `startForeground()`.
 *
 * Lifecycle:
 *   1. Receiver hands us a clip path via intent extra.
 *   2. We call `startForeground()` with a media notification.
 *   3. We acquire AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK + a partial wake lock.
 *   4. We play the file via MediaPlayer.
 *   5. On completion/error, we release everything and call `stopSelf()`.
 *
 * Concurrency: only ONE clip plays at a time. A second alarm firing while
 * a clip is mid-flight will replace the queued player (we stop+release the
 * old one first).
 */
class WhisperPlaybackService : Service() {
    companion object {
        private const val TAG = "WhisperPlayback"
        const val ACTION_PLAY_CLIP = "com.whisperback.alarms.PLAY_CLIP"
        const val EXTRA_CLIP_PATH = "clip_path"
        const val EXTRA_CLIP_TITLE = "clip_title"
        const val EXTRA_PLAYLIST_NAME = "playlist_name"
        const val EXTRA_SCHEDULE_ID = "schedule_id"

        private const val NOTIFICATION_ID = 0xBA77 // distinct from id=1 (active card) and audio_service ids
        private const val CHANNEL_ID = "whisperback_scheduled_playback"
        private const val CHANNEL_NAME = "WhisperBack scheduled playback"
        private const val WAKE_LOCK_TAG = "WhisperBack:scheduledPlayback"
        // Hard cap so a corrupt clip can never lock the FG service open.
        private const val MAX_PLAYBACK_MS = 10 * 60 * 1000L
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioManager: AudioManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        try {
            audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ensureChannel()
        } catch (t: Throwable) {
            Log.e(TAG, "onCreate failed", t)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            // Promote to foreground IMMEDIATELY — must happen within 10 s of
            // startForegroundService() or Android raises
            // ForegroundServiceDidNotStartInTimeException and the system
            // kills us.
            val notification = buildNotification(
                title = intent?.getStringExtra(EXTRA_CLIP_TITLE) ?: "WhisperBack",
                playlistName = intent?.getStringExtra(EXTRA_PLAYLIST_NAME) ?: "Scheduled whisper",
            )
            startInForeground(notification)

            if (intent?.action != ACTION_PLAY_CLIP) {
                Log.w(TAG, "unknown action ${intent?.action}; stopping")
                stopSelfSafely()
                return START_NOT_STICKY
            }

            val clipPath = intent.getStringExtra(EXTRA_CLIP_PATH)
            if (clipPath.isNullOrBlank() || !File(clipPath).exists()) {
                Log.w(TAG, "missing clip path; stopping")
                stopSelfSafely()
                return START_NOT_STICKY
            }

            // Round 21 defense-in-depth: even if a stale alarm survived
            // a cancel-all race, refuse to play when the user has Active
            // OFF. The Dart side mirrors `is_active` into SharedPreferences
            // every time it changes so we can read it without booting
            // Flutter.
            if (!isActiveByPrefs()) {
                Log.w(TAG, "Active=OFF in prefs; skipping playback")
                stopSelfSafely()
                return START_NOT_STICKY
            }

            playClip(clipPath)
        } catch (t: Throwable) {
            Log.e(TAG, "onStartCommand failed", t)
            stopSelfSafely()
        }
        return START_NOT_STICKY
    }

    private fun isActiveByPrefs(): Boolean {
        return try {
            // Default to TRUE so a fresh install (no prefs yet) doesn't
            // suppress a freshly-fired alarm. The Dart side overwrites this
            // every toggle so the FALSE path only kicks in after the user
            // has explicitly turned Active OFF.
            getSharedPreferences("whisperback.alarms.snapshot", Context.MODE_PRIVATE)
                .getBoolean("is_active", true)
        } catch (t: Throwable) {
            Log.e(TAG, "isActiveByPrefs failed", t)
            true
        }
    }

    private fun startInForeground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            // Q+ allow this to throw if the FG-start grant has expired.
            // Fall back to the untyped form — Android logs a warning but
            // still keeps us alive on most OEMs.
            Log.e(TAG, "startForeground with type failed, retrying without", t)
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (t2: Throwable) {
                Log.e(TAG, "startForeground retry failed", t2)
            }
        }
    }

    private fun playClip(clipPath: String) {
        // Stop any clip already playing — second alarm wins.
        releasePlayer()
        acquireWakeLock()
        if (!requestAudioFocus()) {
            Log.w(TAG, "audio focus denied; playing anyway (best effort)")
        }

        val player = MediaPlayer()
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.setDataSource(this, Uri.fromFile(File(clipPath)))
            player.setOnPreparedListener { mp ->
                try {
                    mp.start()
                } catch (t: Throwable) {
                    Log.e(TAG, "MediaPlayer.start failed", t)
                    stopSelfSafely()
                }
            }
            player.setOnCompletionListener {
                Log.i(TAG, "clip complete")
                stopSelfSafely()
            }
            player.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error what=$what extra=$extra")
                stopSelfSafely()
                true
            }
            player.prepareAsync()
            mediaPlayer = player

            // Safety timeout: if the clip somehow runs past 10 minutes we
            // tear ourselves down (the user can't possibly want a 10-minute
            // unattended whisper).
            android.os.Handler(mainLooper).postDelayed(
                {
                    try {
                        if (mediaPlayer === player && player.isPlaying) {
                            Log.w(TAG, "MAX_PLAYBACK_MS reached; stopping")
                            stopSelfSafely()
                        }
                    } catch (_: Throwable) {}
                },
                MAX_PLAYBACK_MS,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "playClip setup failed", t)
            try { player.release() } catch (_: Throwable) {}
            stopSelfSafely()
        }
    }

    private fun requestAudioFocus(): Boolean {
        val mgr = audioManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(true)
                    .build()
                audioFocusRequest = req
                mgr.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                mgr.requestAudioFocus(
                    null,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (t: Throwable) {
            Log.e(TAG, "requestAudioFocus failed", t)
            false
        }
    }

    private fun abandonAudioFocus() {
        val mgr = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { mgr.abandonAudioFocusRequest(it) }
                audioFocusRequest = null
            } else {
                @Suppress("DEPRECATION")
                mgr.abandonAudioFocus(null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "abandonAudioFocus failed", t)
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            lock.setReferenceCounted(false)
            lock.acquire(MAX_PLAYBACK_MS)
            wakeLock = lock
        } catch (t: Throwable) {
            Log.e(TAG, "acquireWakeLock failed", t)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (t: Throwable) {
            Log.e(TAG, "releaseWakeLock failed", t)
        } finally {
            wakeLock = null
        }
    }

    private fun releasePlayer() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "releasePlayer failed", t)
        } finally {
            mediaPlayer = null
        }
    }

    private fun stopSelfSafely() {
        try {
            releasePlayer()
            abandonAudioFocus()
            releaseWakeLock()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (t: Throwable) {
            Log.e(TAG, "stopSelfSafely failed", t)
        }
    }

    override fun onDestroy() {
        try {
            releasePlayer()
            abandonAudioFocus()
            releaseWakeLock()
        } finally {
            super.onDestroy()
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Plays the scheduled whisper when the time arrives"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            mgr.createNotificationChannel(channel)
        } catch (t: Throwable) {
            Log.e(TAG, "ensureChannel failed", t)
        }
    }

    private fun buildNotification(title: String, playlistName: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val smallIcon = resolveSmallIcon()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText("Playing $playlistName")
            .setSmallIcon(smallIcon)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .build()
    }

    private fun resolveSmallIcon(): Int {
        // Prefer dedicated notification asset; fall back to mipmap launcher.
        val res = resources
        val pkg = packageName
        val ids = listOf(
            "ic_stat_whisperback",
            "ic_notification",
            "ic_launcher_foreground",
            "ic_launcher",
        )
        for (name in ids) {
            val id = res.getIdentifier(name, "drawable", pkg)
            if (id != 0) return id
            val mid = res.getIdentifier(name, "mipmap", pkg)
            if (mid != 0) return mid
        }
        return android.R.drawable.ic_media_play
    }
}
