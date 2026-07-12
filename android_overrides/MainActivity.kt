package ir.aspoormehr.asplayer

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

// audio_service needs the activity to extend AudioServiceActivity rather than
// the default FlutterActivity, otherwise the media notification loses the app.
class MainActivity : AudioServiceActivity() {

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "refresh") {
                    WidgetShared.refreshAll(applicationContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasAudioPermission())
            "requestPermission" -> requestAudioPermission(result)
            "scan" -> scanInBackground(result)
            "albumArt" -> result.success(albumArt((call.arguments as? Number)?.toLong() ?: -1L))
            "getVolume" -> result.success(musicVolume())
            "setVolume" -> {
                setMusicVolume((call.arguments as? Double) ?: 1.0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // MARK: - System media volume

    private fun audioManager(): AudioManager =
        getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun musicVolume(): Double {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max == 0) return 0.0
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    private fun setMusicVolume(fraction: Double) {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val index = (fraction.coerceIn(0.0, 1.0) * max).toInt()
        am.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
    }

    // MARK: - Permission

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun hasAudioPermission(): Boolean =
        checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(audioPermission()), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    // MARK: - MediaStore

    /// A large library would block the UI thread, so the query runs off it and
    /// the result is handed back on the main thread, as the channel requires.
    private fun scanInBackground(result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            result.error("no_permission", "Audio permission not granted", null)
            return
        }

        thread {
            val songs = try {
                querySongs()
            } catch (error: Exception) {
                runOnUiThread { result.error("scan_failed", error.message, null) }
                return@thread
            }
            runOnUiThread { result.success(songs) }
        }
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()

        val projection = arrayOf(
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.ALBUM_ID,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val order = "${MediaStore.Audio.Media.TITLE} ASC"

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            null,
            order,
        )?.use { cursor ->
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)

            while (cursor.moveToNext()) {
                val path = cursor.getString(pathColumn) ?: continue
                val artist = cursor.getString(artistColumn)

                songs.add(
                    mapOf(
                        "title" to (cursor.getString(titleColumn) ?: ""),
                        // MediaStore writes this literal string when a file has no artist tag.
                        "artist" to if (artist == null || artist == "<unknown>") "" else artist,
                        "album" to (cursor.getString(albumColumn) ?: ""),
                        "durationMs" to cursor.getLong(durationColumn),
                        "path" to path,
                        "albumId" to cursor.getLong(albumIdColumn),
                    )
                )
            }
        }

        return songs
    }

    /// The cached album thumbnail MediaStore keeps for a song's album — the one
    /// other players show. Many files carry no embedded art, so this fills the
    /// gap. Returns null (and the cover stays blank) on any error.
    private fun albumArt(albumId: Long): ByteArray? {
        if (albumId <= 0) return null
        return try {
            val uri = ContentUris.withAppendedId(
                Uri.parse("content://media/external/audio/albumart"), albumId)
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (error: Exception) {
            null
        }
    }

    private companion object {
        const val CHANNEL = "ir.aspoormehr.asplayer/device_music"
        const val WIDGET_CHANNEL = "ir.aspoormehr.asplayer/widget"
        const val PERMISSION_REQUEST = 4321
    }
}
