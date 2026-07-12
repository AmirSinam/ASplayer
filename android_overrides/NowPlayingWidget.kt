package ir.aspoormehr.asplayer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews

/// Shared plumbing for every home-screen widget size. State is written by the
/// Flutter side into SharedPreferences; controls steer the running MediaSession
/// through media key events, so no plugin is involved.
object WidgetShared {
    const val ACTION_PLAY_PAUSE = "ir.aspoormehr.asplayer.WIDGET_PLAY_PAUSE"
    const val ACTION_NEXT = "ir.aspoormehr.asplayer.WIDGET_NEXT"
    const val ACTION_PREV = "ir.aspoormehr.asplayer.WIDGET_PREV"

    /// Tiffany — the brand accent and the fallback when a cover has no colour.
    const val ACCENT = 0xFF0ABAB5.toInt()

    data class State(val title: String, val artist: String, val cover: String?, val playing: Boolean)

    fun readState(context: Context): State {
        val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return State(
            p.getString("flutter.widget_title", null) ?: "ASplayer",
            p.getString("flutter.widget_artist", null) ?: "",
            p.getString("flutter.widget_cover", null),
            p.getBoolean("flutter.widget_playing", false),
        )
    }

    fun flags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    fun openApp(context: Context): PendingIntent? {
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(context, 0, open, flags())
    }

    /// Control taps always broadcast to NowPlayingWidget, which handles them,
    /// regardless of which widget size was tapped.
    fun control(context: Context, action: String, request: Int): PendingIntent {
        val intent = Intent(context, NowPlayingWidget::class.java).setAction(action)
        return PendingIntent.getBroadcast(context, request, intent, flags())
    }

    fun dispatch(context: Context, keyCode: Int) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
    }

    /// Small rounded thumbnail for the cover slot, optionally ringed in the
    /// cover's own accent colour so it lifts off the backdrop.
    fun thumb(path: String?, size: Int = 220, ring: Int? = null): Bitmap? {
        val src = decode(path) ?: return null
        val scaled = Bitmap.createScaledBitmap(src, size, size, true)
        val radius = size * 0.2f
        val out = roundedSquare(scaled, size, radius)
        if (ring != null) {
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = size * 0.03f
            paint.color = (ring and 0x00FFFFFF) or 0x80000000.toInt()
            val inset = paint.strokeWidth / 2
            canvas.drawRoundRect(
                RectF(inset, inset, size - inset, size - inset), radius, radius, paint)
        }
        return out
    }

    /// A blurred, darkened, rounded backdrop drawn from the cover — the same
    /// look as the in-app now-playing screen. Cheap blur via decode-small then
    /// upscale. Returns null (falls back to the flat dark drawable) on any error.
    fun backdrop(path: String?, w: Int, h: Int, radius: Float): Bitmap? {
        val src = decode(path) ?: return null
        return try {
            val tiny = Bitmap.createScaledBitmap(src, 24, 24, true)
            val big = Bitmap.createScaledBitmap(tiny, w, h, true)
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(big, 0f, 0f, paint)
            paint.xfermode = null
            // Dark scrim, a touch heavier on the right where the text lives.
            val scrim = Paint(Paint.ANTI_ALIAS_FLAG)
            scrim.shader = LinearGradient(
                0f, 0f, w.toFloat(), 0f,
                0xB3060808.toInt(), 0xE6060808.toInt(), Shader.TileMode.CLAMP)
            canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, scrim)
            out
        } catch (e: Exception) {
            null
        }
    }

    /// The round play/pause button as a bitmap, filled with [fill] and a glyph
    /// whose ink stays readable on any fill. Drawn rather than themed because
    /// RemoteViews cannot reliably tint a background drawable.
    fun controlButton(size: Int, fill: Int, playing: Boolean): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = size / 2f
        paint.color = fill
        canvas.drawCircle(r, r, r, paint)

        val lum = (0.299 * Color.red(fill) + 0.587 * Color.green(fill) +
            0.114 * Color.blue(fill)) / 255.0
        paint.color = if (lum > 0.6) 0xFF03211F.toInt() else 0xFFFFFFFF.toInt()

        if (playing) {
            val bw = size * 0.12f
            val bh = size * 0.30f
            val gap = size * 0.09f
            val rr = bw * 0.4f
            canvas.drawRoundRect(RectF(r - gap - bw, r - bh, r - gap, r + bh), rr, rr, paint)
            canvas.drawRoundRect(RectF(r + gap, r - bh, r + gap + bw, r + bh), rr, rr, paint)
        } else {
            val tri = size * 0.30f
            val path = Path()
            path.moveTo(r - tri * 0.5f, r - tri)
            path.lineTo(r - tri * 0.5f, r + tri)
            path.lineTo(r + tri, r)
            path.close()
            canvas.drawPath(path, paint)
        }
        return out
    }

    /// A vivid, mid-bright colour pulled from the cover; tiffany when the art is
    /// greyscale or missing. Mirrors the app's live-tint logic.
    fun accentFrom(path: String?): Int {
        val src = decode(path) ?: return ACCENT
        return try {
            val small = Bitmap.createScaledBitmap(src, 16, 16, true)
            val hsv = FloatArray(3)
            var best = ACCENT
            var bestScore = -1f
            for (y in 0 until small.height) {
                for (x in 0 until small.width) {
                    val c = small.getPixel(x, y)
                    Color.colorToHSV(c, hsv)
                    val score = hsv[1] * (1f - Math.abs(hsv[2] - 0.6f))
                    if (score > bestScore) {
                        bestScore = score
                        best = c
                    }
                }
            }
            Color.colorToHSV(best, hsv)
            if (hsv[1] < 0.15f) return ACCENT
            hsv[1] = hsv[1].coerceIn(0.4f, 0.85f)
            hsv[2] = hsv[2].coerceIn(0.5f, 0.72f)
            Color.HSVToColor(hsv)
        } catch (e: Exception) {
            ACCENT
        }
    }

    /// A translucent variant, for the glass play circle over full-bleed art.
    fun glassy(color: Int): Int = (color and 0x00FFFFFF) or 0xE6000000.toInt()

    /// Centre-cropped cover that fills a rectangle (for the full-bleed square).
    fun fill(path: String?, w: Int, h: Int, radius: Float): Bitmap? {
        val src = decode(path) ?: return null
        val scale = maxOf(w.toFloat() / src.width, h.toFloat() / src.height)
        val sw = (src.width * scale).toInt()
        val sh = (src.height * scale).toInt()
        val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val left = (w - sw) / 2
        val top = (h - sh) / 2
        canvas.drawBitmap(scaled, null, Rect(left, top, left + sw, top + sh), paint)
        return out
    }

    private fun decode(path: String?): Bitmap? =
        if (path == null) null else try { BitmapFactory.decodeFile(path) } catch (e: Exception) { null }

    private fun roundedSquare(src: Bitmap, size: Int, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), radius, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return out
    }

    /// Repaints every placed widget of every size. Called from Flutter.
    fun refreshAll(context: Context) {
        for (cls in listOf(
            NowPlayingWidget::class.java,
            SmallWidget::class.java,
            LargeWidget::class.java,
        )) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            val intent = Intent(context, cls).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }
}

/// Compact 4x1: cover, title/artist, prev/play/next.
class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val st = WidgetShared.readState(context)
        val accent = WidgetShared.accentFrom(st.cover)
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_now_playing)
            v.setTextViewText(R.id.widget_title, st.title)
            v.setTextViewText(R.id.widget_artist, st.artist)

            val backdrop = WidgetShared.backdrop(st.cover, 720, 200, 56f)
            if (backdrop != null) {
                v.setImageViewBitmap(R.id.widget_backdrop, backdrop)
                v.setViewVisibility(R.id.widget_backdrop, View.VISIBLE)
            } else {
                v.setViewVisibility(R.id.widget_backdrop, View.GONE)
            }

            val thumb = WidgetShared.thumb(st.cover, 220, accent)
            if (thumb != null) v.setImageViewBitmap(R.id.widget_cover, thumb)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)

            v.setImageViewBitmap(R.id.widget_play, WidgetShared.controlButton(150, accent, st.playing))
            v.setInt(R.id.widget_label, "setTextColor", accent)
            v.setInt(R.id.widget_dot, "setColorFilter", accent)

            WidgetShared.openApp(context)?.let { v.setOnClickPendingIntent(R.id.widget_info, it) }
            v.setOnClickPendingIntent(R.id.widget_play, WidgetShared.control(context, WidgetShared.ACTION_PLAY_PAUSE, 1))
            v.setOnClickPendingIntent(R.id.widget_next, WidgetShared.control(context, WidgetShared.ACTION_NEXT, 2))
            v.setOnClickPendingIntent(R.id.widget_prev, WidgetShared.control(context, WidgetShared.ACTION_PREV, 3))
            manager.updateAppWidget(id, v)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetShared.ACTION_PLAY_PAUSE -> WidgetShared.dispatch(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            WidgetShared.ACTION_NEXT -> WidgetShared.dispatch(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            WidgetShared.ACTION_PREV -> WidgetShared.dispatch(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            else -> return
        }
        WidgetShared.refreshAll(context)
    }
}

/// Small 2x2: full-bleed cover with a centred play/pause. Tap art to open.
class SmallWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val st = WidgetShared.readState(context)
        val accent = WidgetShared.accentFrom(st.cover)
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_small)
            val cover = WidgetShared.fill(st.cover, 360, 360, 60f)
            if (cover != null) v.setImageViewBitmap(R.id.widget_cover, cover)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
            v.setImageViewBitmap(R.id.widget_play,
                WidgetShared.controlButton(160, WidgetShared.glassy(accent), st.playing))
            WidgetShared.openApp(context)?.let { v.setOnClickPendingIntent(R.id.widget_cover, it) }
            v.setOnClickPendingIntent(R.id.widget_play, WidgetShared.control(context, WidgetShared.ACTION_PLAY_PAUSE, 1))
            manager.updateAppWidget(id, v)
        }
    }
}

/// Large 4x2: big cover, title/artist, full controls.
class LargeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val st = WidgetShared.readState(context)
        val accent = WidgetShared.accentFrom(st.cover)
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_large)
            v.setTextViewText(R.id.widget_title, st.title)
            v.setTextViewText(R.id.widget_artist, st.artist)

            val backdrop = WidgetShared.backdrop(st.cover, 720, 380, 60f)
            if (backdrop != null) {
                v.setImageViewBitmap(R.id.widget_backdrop, backdrop)
                v.setViewVisibility(R.id.widget_backdrop, View.VISIBLE)
            } else {
                v.setViewVisibility(R.id.widget_backdrop, View.GONE)
            }

            val thumb = WidgetShared.thumb(st.cover, 300, accent)
            if (thumb != null) v.setImageViewBitmap(R.id.widget_cover, thumb)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)

            v.setImageViewBitmap(R.id.widget_play, WidgetShared.controlButton(160, accent, st.playing))
            v.setInt(R.id.widget_label, "setTextColor", accent)
            v.setInt(R.id.widget_dot, "setColorFilter", accent)

            WidgetShared.openApp(context)?.let { v.setOnClickPendingIntent(R.id.widget_info, it) }
            v.setOnClickPendingIntent(R.id.widget_play, WidgetShared.control(context, WidgetShared.ACTION_PLAY_PAUSE, 1))
            v.setOnClickPendingIntent(R.id.widget_next, WidgetShared.control(context, WidgetShared.ACTION_NEXT, 2))
            v.setOnClickPendingIntent(R.id.widget_prev, WidgetShared.control(context, WidgetShared.ACTION_PREV, 3))
            manager.updateAppWidget(id, v)
        }
    }
}
