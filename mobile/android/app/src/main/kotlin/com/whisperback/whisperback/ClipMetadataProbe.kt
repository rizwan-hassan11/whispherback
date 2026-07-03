package com.whisperback.whisperback

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import java.io.File

/**
 * Round 24 — native duration probe backed by `MediaMetadataRetriever`.
 *
 * Why native, not `just_audio`?
 *
 *   `just_audio`'s Dart-side `probe.setFilePath(path)` binds the file to
 *   the shared `AudioSession`. On Samsung One UI 12+ / Vivo Funtouch,
 *   this either (a) silently consumes audio focus so the very next real
 *   `play()` call is dropped, or (b) auto-starts the probe player
 *   through the media session. Both were reproduced on the QA device
 *   and were the "first recorded clip won't play" bug the app has
 *   fought since Round 6.
 *
 *   `MediaMetadataRetriever` reads the container header directly with
 *   no MediaPlayer / MediaSession involvement. It is the same call the
 *   OS itself uses for Files app duration display, so it is reliable
 *   on every device we've tested (Samsung / Xiaomi / Vivo / Pixel).
 *
 *   The user's QA "clip card only shows 0:00 instead of the actual
 *   length" was the `just_audio` probe silently failing on their
 *   device (either the setFilePath timed out or returned null). This
 *   native fallback closes that gap.
 */
object ClipMetadataProbe {
    private const val TAG = "ClipMetadataProbe"

    /**
     * Returns the clip's duration in milliseconds, or 0 if we couldn't
     * determine it. Never throws.
     */
    fun readDurationMs(context: Context, filePath: String): Long {
        if (filePath.isBlank()) return 0L
        val file = File(filePath)
        if (!file.exists() || file.length() == 0L) return 0L
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.fromFile(file))
            val raw = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            raw?.toLongOrNull()?.coerceAtLeast(0L) ?: 0L
        } catch (t: Throwable) {
            Log.w(TAG, "readDurationMs failed for $filePath", t)
            0L
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }
}
