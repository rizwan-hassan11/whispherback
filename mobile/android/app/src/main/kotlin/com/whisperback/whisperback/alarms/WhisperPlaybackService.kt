package com.whisperback.whisperback.alarms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import com.whisperback.whisperback.MainActivity
import java.io.File

/**
 * Round 21/22 — typed `mediaPlayback` foreground service that owns the
 * scheduled-audio MediaPlayer.
 *
 * Round 22 changes (responding to user QA):
 *   • Audio attributes flipped from USAGE_ALARM → USAGE_MEDIA /
 *     CONTENT_TYPE_MUSIC + STREAM_MUSIC. The user's QA report
 *     "schedule plays at full volume although I set my volume low" was
 *     the OS routing alarm-class audio through the alarm volume stream,
 *     which on every Android device defaults to 100 % and ignores the
 *     media slider. Scheduled clips are music, not alarms — they must
 *     follow the media volume the user already trusts.
 *   • Honors a user-set playback volume from SharedPreferences
 *     (`playback_volume`, 0.0–1.0) which the Dart side writes whenever
 *     the in-app volume slider moves, or 1.0 by default.
 *   • Posts a MediaStyle notification with PAUSE / RESUME / STOP actions
 *     so the user can control playback right from the notification
 *     shade — exactly what they expected from "tapping pause/resume in
 *     notification bar".
 *   • Mirrors playback state (PLAYING / PAUSED / STOPPED) +
 *     current-clip metadata into SharedPreferences so the Dart side can
 *     pick it up on app launch / resume and show the mini-player even
 *     for a scheduled clip that started while the app was closed.
 *   • New actions: ACTION_PAUSE / ACTION_RESUME / ACTION_STOP_NOW
 *     handled by the same service singleton, so Dart can call
 *     `pauseNative()` / `resumeNative()` / `stopNative()` over the
 *     platform channel and they reach this MediaPlayer immediately.
 */
class WhisperPlaybackService : Service() {
    companion object {
        private const val TAG = "WhisperPlayback"
        const val ACTION_PLAY_CLIP = "com.whisperback.alarms.PLAY_CLIP"
        const val ACTION_PAUSE = "com.whisperback.alarms.PAUSE"
        const val ACTION_RESUME = "com.whisperback.alarms.RESUME"
        const val ACTION_STOP_NOW = "com.whisperback.alarms.STOP_NOW"
        const val EXTRA_CLIP_PATH = "clip_path"
        const val EXTRA_CLIP_TITLE = "clip_title"
        const val EXTRA_PLAYLIST_NAME = "playlist_name"
        const val EXTRA_SCHEDULE_ID = "schedule_id"
        const val EXTRA_CLIP_QUEUE_JSON = "clip_queue_json"

        // Distinct from notification_service.dart's _ongoingId (1), the
        // keep-alive service id (0x57424B), and audio_service's IDs.
        private const val NOTIFICATION_ID = 0xBA77
        private const val CHANNEL_ID = "whisperback_scheduled_playback"
        private const val CHANNEL_NAME = "WhisperBack scheduled playback"
        private const val WAKE_LOCK_TAG = "WhisperBack:scheduledPlayback"
        // Hard cap so a corrupt clip can never lock the FG service open.
        // 2 hours covers long multi-clip playlist fires on slow devices.
        private const val MAX_PLAYBACK_MS = 2 * 60 * 60 * 1000L
        private const val WATCHDOG_INTERVAL_MS = 2_000L

        // Round 22 — single global state pref so the Dart side can poll
        // it on app launch/resume.
        const val STATE_PREFS = "whisperback.alarms.playback_state"
        const val KEY_STATE = "state" // "idle" | "playing" | "paused"
        const val KEY_CURRENT_PATH = "clip_path"
        const val KEY_CURRENT_TITLE = "clip_title"
        const val KEY_CURRENT_PLAYLIST = "playlist_name"
        const val KEY_CURRENT_SCHEDULE_ID = "schedule_id"
        const val KEY_VOLUME = "playback_volume" // float 0.0–1.0
        // Round 27 — real clip progress for the Flutter mini-player.
        // Previously the mini-player read the Dart silence keep-alive's
        // 10-second duration while native MediaPlayer owned the clip.
        const val KEY_DURATION_MS = "duration_ms"
        const val KEY_POSITION_MS = "position_ms"
        /// Set true while MediaPlayer owns the stream so Dart/Kotlin
        /// keep-alive can refuse to restart ExoPlayer silence underneath.
        const val KEY_NATIVE_ACTIVE = "native_playback_active"

        const val STATE_IDLE = "idle"
        const val STATE_PLAYING = "playing"
        const val STATE_PAUSED = "paused"

        // Optional Dart listener — set by the Flutter side via
        // MainActivity so notification-button presses surface in the
        // coordinator's pause/play snapshot. Null when the app process
        // isn't running, which is fine: state is also mirrored in prefs.
        @Volatile var stateListener: ((
            state: String,
            clipPath: String?,
            clipTitle: String?,
            playlistName: String?,
            scheduleId: String?,
            durationMs: Long,
            positionMs: Long,
        ) -> Unit)? = null
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioManager: AudioManager? = null
    private var progressHandler: android.os.Handler? = null
    private var currentDurationMs: Long = 0L
    private var resumeAfterFocusGain: Boolean = false

    /// True ONLY after an explicit user pause (notification / mini-player /
    /// Dart pauseNative). Focus-loss, OEM ducking, and silence keep-alive
    /// must NEVER set this — Round 30 anti-auto-pause contract.
    private var userPaused: Boolean = false

    /// True while we intend the clip to be audible (between prepare/start
    /// and completion / user pause / stop). Watchdog uses this to restart
    /// MediaPlayer if an OEM silently stops it.
    private var wantPlaying: Boolean = false

    private var currentClipPath: String? = null
    private var currentClipTitle: String = "WhisperBack"
    private var currentPlaylistName: String = "Scheduled whisper"
    private var currentScheduleId: String? = null
    private var clipQueue: List<Pair<String, String>> = emptyList()
    private var clipQueueIndex: Int = 0
    private var errorRestarts: Int = 0

    private val progressTicker = object : Runnable {
        override fun run() {
            try {
                val player = mediaPlayer
                if (player != null && player.isPlaying) {
                    val pos = player.currentPosition.toLong().coerceAtLeast(0L)
                    writeProgress(pos, currentDurationMs)
                    // Lightweight progress push so the mini-player scrubber
                    // stays honest without requiring a full state transition.
                    notifyListener(STATE_PLAYING)
                    renewWakeLockIfNeeded()
                }
            } catch (t: Throwable) {
                Log.w(TAG, "progressTicker failed", t)
            }
            progressHandler?.postDelayed(this, 500L)
        }
    }

    private val playbackWatchdog = object : Runnable {
        override fun run() {
            try {
                ensureStillPlaying("watchdog")
            } catch (t: Throwable) {
                Log.w(TAG, "playbackWatchdog failed", t)
            }
            progressHandler?.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

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
            // ForegroundServiceDidNotStartInTimeException and kills us.
            val title = intent?.getStringExtra(EXTRA_CLIP_TITLE) ?: currentClipTitle
            val playlist = intent?.getStringExtra(EXTRA_PLAYLIST_NAME) ?: currentPlaylistName
            val isCurrentlyPlaying = mediaPlayer?.isPlaying == true
            val notification = buildNotification(
                title = title,
                playlistName = playlist,
                isPlaying = isCurrentlyPlaying,
            )
            startInForeground(notification)

            when (intent?.action) {
                ACTION_PLAY_CLIP -> handlePlayCommand(intent)
                ACTION_PAUSE -> handlePauseCommand()
                ACTION_RESUME -> handleResumeCommand()
                ACTION_STOP_NOW -> {
                    Log.i(TAG, "stop requested via notification/Dart")
                    stopSelfSafely()
                }
                else -> {
                    // Round 30: null/unknown action must NOT tear down an
                    // in-flight clip. OEMs redeliver the service with a
                    // null Intent after process reclaim — stopping here
                    // was one auto-pause / silent-kill path.
                    if (mediaPlayer != null) {
                        Log.w(
                            TAG,
                            "unknown action ${intent?.action}; keeping current playback",
                        )
                        ensureStillPlaying("onStartCommand-null")
                    } else {
                        Log.w(TAG, "unknown action ${intent?.action}; no player")
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onStartCommand failed", t)
            // Don't stopSelf if we still have a live player — preserve audio.
            if (mediaPlayer == null) {
                stopSelfSafely()
            }
        }
        return START_STICKY
    }

    private fun handlePlayCommand(intent: Intent) {
        val clipPath = intent.getStringExtra(EXTRA_CLIP_PATH)
        if (clipPath.isNullOrBlank() || !File(clipPath).exists()) {
            Log.w(TAG, "missing clip path; stopping")
            stopSelfSafely()
            return
        }

        // Round 21 defense-in-depth: refuse to play when Active=OFF.
        if (!isActiveByPrefs()) {
            Log.w(TAG, "Active=OFF in prefs; skipping playback")
            stopSelfSafely()
            return
        }

        // Round 31: if this exact clip is already playing, ignore the
        // duplicate PLAY_CLIP (OEM redelivery / overlapping schedule)
        // instead of releasePlayer() which sounded like auto-pause.
        val alreadySame = mediaPlayer != null &&
            wantPlaying &&
            !userPaused &&
            currentClipPath == clipPath &&
            (mediaPlayer?.isPlaying == true)
        if (alreadySame) {
            Log.i(TAG, "duplicate PLAY_CLIP for same path; keeping current player")
            writeState(STATE_PLAYING)
            postPlaybackNotification(isPlaying = true)
            notifyListener(STATE_PLAYING)
            return
        }

        currentClipPath = clipPath
        currentClipTitle = intent.getStringExtra(EXTRA_CLIP_TITLE) ?: "WhisperBack"
        currentPlaylistName = intent.getStringExtra(EXTRA_PLAYLIST_NAME) ?: "Scheduled whisper"
        currentScheduleId = intent.getStringExtra(EXTRA_SCHEDULE_ID)
        clipQueue = parseClipQueue(intent.getStringExtra(EXTRA_CLIP_QUEUE_JSON), clipPath, currentClipTitle)
        clipQueueIndex = 0
        // Stamp native-active BEFORE prepareAsync so a concurrent Dart
        // enterForeground / heartbeat cannot restart silence in the gap.
        userPaused = false
        wantPlaying = true
        errorRestarts = 0
        writeState(STATE_PLAYING)
        playClip(clipPath)
    }

    private fun handlePauseCommand() {
        try {
            // Explicit user pause — the ONLY path that may leave the
            // player paused without the watchdog restarting it.
            userPaused = true
            wantPlaying = false
            resumeAfterFocusGain = false
            val player = mediaPlayer
            if (player == null) {
                Log.w(TAG, "pause requested with no active player")
                postPlaybackNotification(isPlaying = false)
                writeState(STATE_PAUSED)
                notifyListener(STATE_PAUSED)
                return
            }
            stopProgressTicker()
            stopWatchdog()
            if (player.isPlaying) {
                player.pause()
            }
            writeProgress(player.currentPosition.toLong().coerceAtLeast(0L), currentDurationMs)
            writeState(STATE_PAUSED)
            postPlaybackNotification(isPlaying = false)
            notifyListener(STATE_PAUSED)
        } catch (t: Throwable) {
            Log.e(TAG, "handlePauseCommand failed", t)
        }
    }

    private fun handleResumeCommand() {
        try {
            userPaused = false
            wantPlaying = true
            val player = mediaPlayer ?: return run {
                Log.w(TAG, "resume requested with no active player")
            }
            if (player.isPlaying) {
                postPlaybackNotification(isPlaying = true)
                writeState(STATE_PLAYING)
                notifyListener(STATE_PLAYING)
                startWatchdog()
                return
            }
            if (!requestAudioFocus()) {
                Log.w(TAG, "audio focus denied on resume; playing anyway")
            }
            player.start()
            writeState(STATE_PLAYING)
            startProgressTicker()
            startWatchdog()
            postPlaybackNotification(isPlaying = true)
            notifyListener(STATE_PLAYING)
        } catch (t: Throwable) {
            Log.e(TAG, "handleResumeCommand failed", t)
        }
    }

    private fun postPlaybackNotification(isPlaying: Boolean) {
        try {
            val notification = buildNotification(
                title = currentClipTitle,
                playlistName = currentPlaylistName,
                isPlaying = isPlaying,
            )
            val mgr =
                getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            mgr?.notify(NOTIFICATION_ID, notification)
        } catch (t: Throwable) {
            Log.e(TAG, "postPlaybackNotification failed", t)
        }
    }

    private fun isActiveByPrefs(): Boolean {
        return try {
            // Default to TRUE so a fresh install (no prefs yet) doesn't
            // suppress a freshly-fired alarm.
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
        stopProgressTicker()
        stopWatchdog()
        releasePlayer()
        currentDurationMs = 0L
        resumeAfterFocusGain = false
        userPaused = false
        wantPlaying = true
        acquireWakeLock()
        if (!requestAudioFocus()) {
            Log.w(TAG, "audio focus denied; playing anyway (best effort)")
        }

        val player = MediaPlayer()
        try {
            // Round 22 — USAGE_MEDIA + CONTENT_TYPE_MUSIC + STREAM_MUSIC.
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            // Round 30: MediaPlayer-owned wake mode + service wake lock.
            try {
                player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            } catch (t: Throwable) {
                Log.w(TAG, "setWakeMode failed", t)
            }
            player.setDataSource(this, Uri.fromFile(File(clipPath)))
            player.setOnPreparedListener { mp ->
                try {
                    if (userPaused) {
                        Log.i(TAG, "prepared but user already paused; not starting")
                        return@setOnPreparedListener
                    }
                    val vol = readUserVolume()
                    mp.setVolume(vol, vol)
                    currentDurationMs = try {
                        mp.duration.toLong().coerceAtLeast(0L)
                    } catch (_: Throwable) {
                        0L
                    }
                    writeProgress(0L, currentDurationMs)
                    wantPlaying = true
                    mp.start()
                    writeState(STATE_PLAYING)
                    startProgressTicker()
                    startWatchdog()
                    notifyListener(STATE_PLAYING)
                    val notification = buildNotification(
                        title = currentClipTitle,
                        playlistName = currentPlaylistName,
                        isPlaying = true,
                    )
                    val mgr = getSystemService(Context.NOTIFICATION_SERVICE)
                        as? NotificationManager
                    mgr?.notify(NOTIFICATION_ID, notification)
                } catch (t: Throwable) {
                    Log.e(TAG, "MediaPlayer.start failed", t)
                    stopSelfSafely()
                }
            }
            player.setOnCompletionListener {
                Log.i(TAG, "clip complete at queue index $clipQueueIndex / ${clipQueue.size}")
                val nextIndex = clipQueueIndex + 1
                if (nextIndex < clipQueue.size) {
                    val (nextPath, nextTitle) = clipQueue[nextIndex]
                    if (File(nextPath).exists()) {
                        clipQueueIndex = nextIndex
                        currentClipPath = nextPath
                        currentClipTitle = nextTitle
                        playClip(nextPath)
                        return@setOnCompletionListener
                    }
                }
                wantPlaying = false
                stopSelfSafely()
            }
            player.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error what=$what extra=$extra")
                if (!userPaused && wantPlaying && errorRestarts < 1) {
                    errorRestarts++
                    try {
                        Log.w(TAG, "restarting clip after MediaPlayer error")
                        playClip(clipPath)
                        return@setOnErrorListener true
                    } catch (t: Throwable) {
                        Log.e(TAG, "error-path restart failed", t)
                    }
                }
                wantPlaying = false
                stopSelfSafely()
                true
            }
            player.prepareAsync()
            mediaPlayer = player
        } catch (t: Throwable) {
            Log.e(TAG, "playClip setup failed", t)
            try { player.release() } catch (_: Throwable) {}
            stopSelfSafely()
        }
    }

    private fun readUserVolume(): Float {
        return try {
            val v = getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
                .getFloat(KEY_VOLUME, 1.0f)
            v.coerceIn(0f, 1f)
        } catch (t: Throwable) {
            1.0f
        }
    }

    private fun parseClipQueue(
        json: String?,
        fallbackPath: String,
        fallbackTitle: String,
    ): List<Pair<String, String>> {
        if (!json.isNullOrBlank()) {
            try {
                val arr = org.json.JSONArray(json)
                val out = mutableListOf<Pair<String, String>>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val path = obj.optString("path").takeIf { it.isNotBlank() } ?: continue
                    val title = obj.optString("title").ifBlank { "WhisperBack" }
                    out.add(path to title)
                }
                if (out.isNotEmpty()) return out
            } catch (t: Throwable) {
                Log.w(TAG, "parseClipQueue failed; using single clip", t)
            }
        }
        return listOf(fallbackPath to fallbackTitle)
    }

    private fun writeState(state: String) {
        try {
            val editor = getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_STATE, state)
            // Round 29: advertise "native owns the stream" the instant we
            // leave idle so Dart can refuse to start ExoPlayer silence
            // underneath us — even before the Flutter engine receives the
            // method-channel event (cold start / process reclaim race).
            val nativeActive = state == STATE_PLAYING || state == STATE_PAUSED
            editor.putBoolean(KEY_NATIVE_ACTIVE, nativeActive)
            if (state == STATE_IDLE) {
                editor.remove(KEY_CURRENT_PATH)
                    .remove(KEY_CURRENT_TITLE)
                    .remove(KEY_CURRENT_PLAYLIST)
                    .remove(KEY_CURRENT_SCHEDULE_ID)
                    .remove(KEY_DURATION_MS)
                    .remove(KEY_POSITION_MS)
            } else {
                editor.putString(KEY_CURRENT_PATH, currentClipPath ?: "")
                    .putString(KEY_CURRENT_TITLE, currentClipTitle)
                    .putString(KEY_CURRENT_PLAYLIST, currentPlaylistName)
                    .putString(KEY_CURRENT_SCHEDULE_ID, currentScheduleId ?: "")
                    .putLong(KEY_DURATION_MS, currentDurationMs)
            }
            editor.apply()
        } catch (t: Throwable) {
            Log.e(TAG, "writeState failed", t)
        }
    }

    private fun writeProgress(positionMs: Long, durationMs: Long) {
        try {
            getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_POSITION_MS, positionMs)
                .putLong(KEY_DURATION_MS, durationMs)
                .apply()
        } catch (t: Throwable) {
            Log.e(TAG, "writeProgress failed", t)
        }
    }

    private fun startProgressTicker() {
        if (progressHandler == null) {
            progressHandler = android.os.Handler(mainLooper)
        }
        progressHandler?.removeCallbacks(progressTicker)
        progressHandler?.postDelayed(progressTicker, 500L)
    }

    private fun stopProgressTicker() {
        progressHandler?.removeCallbacks(progressTicker)
    }

    private fun notifyListener(state: String) {
        try {
            val pos = try {
                mediaPlayer?.currentPosition?.toLong()?.coerceAtLeast(0L) ?: 0L
            } catch (_: Throwable) {
                0L
            }
            stateListener?.invoke(
                state,
                currentClipPath,
                currentClipTitle,
                currentPlaylistName,
                currentScheduleId,
                currentDurationMs,
                pos,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "notifyListener failed (handled)", t)
        }
    }

    /**
     * Round 30 — scheduled whispers must NOT pause on audio-focus loss.
     *
     * Samsung / Xiaomi / Vivo fire AUDIOFOCUS_LOSS_TRANSIENT for
     * notifications, assistant blips, and even our own silence keep-alive.
     * Pausing there left the clip stuck paused when GAIN never arrived —
     * the exact "auto pause" QA report. Product contract: only stop on
     * clip completion or an explicit user pause/stop. Focus changes only
     * duck volume; the watchdog restarts if an OEM still mutes the player.
     */
    private fun requestAudioFocus(): Boolean {
        val mgr = audioManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener { focusChange ->
                        onAudioFocusChanged(focusChange)
                    }
                    .build()
                audioFocusRequest = req
                mgr.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                mgr.requestAudioFocus(
                    { focusChange -> onAudioFocusChanged(focusChange) },
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (t: Throwable) {
            Log.e(TAG, "requestAudioFocus failed", t)
            false
        }
    }

    private fun onAudioFocusChanged(focusChange: Int) {
        try {
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
                -> {
                    // Duck only — NEVER pause. Auto-pause on focus loss was
                    // the #1 cause of mid-schedule silence on OEM devices.
                    Log.i(TAG, "audio focus change=$focusChange; ducking (no pause)")
                    try {
                        mediaPlayer?.setVolume(0.35f, 0.35f)
                    } catch (_: Throwable) {}
                    // Kick the watchdog so if the OEM still stopped the
                    // player underneath us we restart within 2s.
                    ensureStillPlaying("focus-loss-$focusChange")
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    try {
                        val vol = readUserVolume()
                        mediaPlayer?.setVolume(vol, vol)
                    } catch (_: Throwable) {}
                    resumeAfterFocusGain = false
                    ensureStillPlaying("focus-gain")
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onAudioFocusChanged failed", t)
        }
    }

    private fun startWatchdog() {
        if (progressHandler == null) {
            progressHandler = android.os.Handler(mainLooper)
        }
        progressHandler?.removeCallbacks(playbackWatchdog)
        progressHandler?.postDelayed(playbackWatchdog, WATCHDOG_INTERVAL_MS)
    }

    private fun stopWatchdog() {
        progressHandler?.removeCallbacks(playbackWatchdog)
    }

    /**
     * If we intend to be playing and the user did not pause, but
     * MediaPlayer is not playing, restart it. Covers OEM silent stops,
     * focus races with Dart silence, and Doze quirks.
     */
    private fun ensureStillPlaying(reason: String) {
        if (userPaused || !wantPlaying) return
        val player = mediaPlayer ?: return
        try {
            if (player.isPlaying) return
            Log.w(TAG, "ensureStillPlaying($reason): restarting MediaPlayer")
            if (!requestAudioFocus()) {
                Log.w(TAG, "ensureStillPlaying: focus denied; starting anyway")
            }
            try {
                val vol = readUserVolume()
                player.setVolume(vol, vol)
            } catch (_: Throwable) {}
            player.start()
            writeState(STATE_PLAYING)
            startProgressTicker()
            postPlaybackNotification(isPlaying = true)
            notifyListener(STATE_PLAYING)
        } catch (t: Throwable) {
            Log.e(TAG, "ensureStillPlaying($reason) failed", t)
        }
    }

    private fun renewWakeLockIfNeeded() {
        try {
            val lock = wakeLock
            if (lock == null || !lock.isHeld) {
                acquireWakeLock()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "renewWakeLockIfNeeded failed", t)
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
            wantPlaying = false
            userPaused = false
            stopProgressTicker()
            stopWatchdog()
            releasePlayer()
            abandonAudioFocus()
            releaseWakeLock()
            currentDurationMs = 0L
            resumeAfterFocusGain = false
            writeState(STATE_IDLE)
            notifyListener(STATE_IDLE)
            currentClipPath = null
            currentScheduleId = null
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
            wantPlaying = false
            stopProgressTicker()
            stopWatchdog()
            releasePlayer()
            abandonAudioFocus()
            releaseWakeLock()
            currentDurationMs = 0L
            resumeAfterFocusGain = false
            writeState(STATE_IDLE)
            notifyListener(STATE_IDLE)
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

    private fun buildNotification(
        title: String,
        playlistName: String,
        isPlaying: Boolean,
    ): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val pausePI = servicePendingIntent(ACTION_PAUSE, 101)
        val resumePI = servicePendingIntent(ACTION_RESUME, 102)
        val stopPI = servicePendingIntent(ACTION_STOP_NOW, 103)
        val smallIcon = resolveSmallIcon()
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Playing $playlistName")
            .setSmallIcon(smallIcon)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // Round 30: do NOT attach a deleteIntent that STOPs playback.
            // Some OEMs auto-dismiss / recreate ongoing notifications and
            // were killing the MediaPlayer mid-clip.
        if (isPlaying) {
            builder.addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    pausePI,
                ),
            )
        } else {
            builder.addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "Resume",
                    resumePI,
                ),
            )
        }
        builder.addAction(
            NotificationCompat.Action(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPI,
            ),
        )
        builder.setStyle(
            MediaStyle().setShowActionsInCompactView(0, 1),
        )
        return builder.build()
    }

    private fun servicePendingIntent(action: String, requestId: Int): PendingIntent {
        val intent = Intent(this, WhisperPlaybackService::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, requestId, intent, flags)
        } else {
            PendingIntent.getService(this, requestId, intent, flags)
        }
    }

    private fun resolveSmallIcon(): Int {
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
