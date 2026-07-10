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
import android.graphics.RectF
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews

/// A home-screen now-playing widget. State is written to SharedPreferences by
/// the Flutter side; control buttons steer the running MediaSession via media
/// key events, so no plugin is involved.
class NowPlayingWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PLAY_PAUSE -> dispatch(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            ACTION_NEXT -> dispatch(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            ACTION_PREV -> dispatch(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        }
    }

    private fun dispatch(context: Context, keyCode: Int) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        renderAll(context)
    }

    private fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java))
        for (id in ids) render(context, manager, id)
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val title = prefs.getString("flutter.widget_title", null) ?: "ASplayer"
        val artist = prefs.getString("flutter.widget_artist", null) ?: ""
        val coverPath = prefs.getString("flutter.widget_cover", null)
        val playing = prefs.getBoolean("flutter.widget_playing", false)

        val views = RemoteViews(context.packageName, R.layout.widget_now_playing)
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)
        views.setImageViewResource(
            R.id.widget_play,
            if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        )

        val cover = coverPath?.let { rounded(it) }
        if (cover != null) {
            views.setImageViewBitmap(R.id.widget_cover, cover)
        } else {
            views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
        }

        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { open ->
            views.setOnClickPendingIntent(
                R.id.widget_info,
                PendingIntent.getActivity(context, 0, open, flags()),
            )
        }
        views.setOnClickPendingIntent(R.id.widget_play, broadcast(context, ACTION_PLAY_PAUSE, 1))
        views.setOnClickPendingIntent(R.id.widget_next, broadcast(context, ACTION_NEXT, 2))
        views.setOnClickPendingIntent(R.id.widget_prev, broadcast(context, ACTION_PREV, 3))

        manager.updateAppWidget(id, views)
    }

    private fun broadcast(context: Context, action: String, request: Int): PendingIntent {
        val intent = Intent(context, NowPlayingWidget::class.java).setAction(action)
        return PendingIntent.getBroadcast(context, request, intent, flags())
    }

    private fun flags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun rounded(path: String): Bitmap? {
        return try {
            val src = BitmapFactory.decodeFile(path) ?: return null
            val size = 256
            val scaled = Bitmap.createScaledBitmap(src, size, size, true)
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            canvas.drawRoundRect(rect, 44f, 44f, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(scaled, 0f, 0f, paint)
            out
        } catch (error: Exception) {
            null
        }
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "ir.aspoormehr.asplayer.WIDGET_PLAY_PAUSE"
        const val ACTION_NEXT = "ir.aspoormehr.asplayer.WIDGET_NEXT"
        const val ACTION_PREV = "ir.aspoormehr.asplayer.WIDGET_PREV"

        /// Called from the Flutter side (via MainActivity) after the track or
        /// play state changes, to repaint every placed widget.
        fun refresh(context: Context) {
            val intent = Intent(context, NowPlayingWidget::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java))
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }
}
