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
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews

/// Shared plumbing for every home-screen widget size. State is written by the
/// Flutter side into SharedPreferences; controls steer the running MediaSession
/// through media key events, so no plugin is involved.
object WidgetShared {
    const val ACTION_PLAY_PAUSE = "ir.aspoormehr.asplayer.WIDGET_PLAY_PAUSE"
    const val ACTION_NEXT = "ir.aspoormehr.asplayer.WIDGET_NEXT"
    const val ACTION_PREV = "ir.aspoormehr.asplayer.WIDGET_PREV"

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

    /// Small rounded thumbnail for the cover slot.
    fun thumb(path: String?, size: Int = 220): Bitmap? {
        val src = decode(path) ?: return null
        val scaled = Bitmap.createScaledBitmap(src, size, size, true)
        return roundedSquare(scaled, size, size * 0.2f)
    }

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
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_now_playing)
            v.setTextViewText(R.id.widget_title, st.title)
            v.setTextViewText(R.id.widget_artist, st.artist)
            v.setImageViewResource(R.id.widget_play,
                if (st.playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
            val thumb = WidgetShared.thumb(st.cover)
            if (thumb != null) v.setImageViewBitmap(R.id.widget_cover, thumb)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
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
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_small)
            val cover = WidgetShared.fill(st.cover, 320, 320, 56f)
            if (cover != null) v.setImageViewBitmap(R.id.widget_cover, cover)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
            v.setImageViewResource(R.id.widget_play,
                if (st.playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
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
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_large)
            v.setTextViewText(R.id.widget_title, st.title)
            v.setTextViewText(R.id.widget_artist, st.artist)
            v.setImageViewResource(R.id.widget_play,
                if (st.playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
            val thumb = WidgetShared.thumb(st.cover, 300)
            if (thumb != null) v.setImageViewBitmap(R.id.widget_cover, thumb)
            else v.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
            WidgetShared.openApp(context)?.let { v.setOnClickPendingIntent(R.id.widget_info, it) }
            v.setOnClickPendingIntent(R.id.widget_play, WidgetShared.control(context, WidgetShared.ACTION_PLAY_PAUSE, 1))
            v.setOnClickPendingIntent(R.id.widget_next, WidgetShared.control(context, WidgetShared.ACTION_NEXT, 2))
            v.setOnClickPendingIntent(R.id.widget_prev, WidgetShared.control(context, WidgetShared.ACTION_PREV, 3))
            manager.updateAppWidget(id, v)
        }
    }
}
