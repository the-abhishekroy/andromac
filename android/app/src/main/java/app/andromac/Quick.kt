package app.andromac

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.RemoteViews

/** Shared logic for the widget, Quick Settings tiles and notification buttons. Reuses Settings, Link and LinkService; owns no state. */
object Quick {
    enum class Mode { NOT_PAIRED, PAUSED, CONNECTING, CONNECTED, OFFLINE }

    fun mode(ctx: Context): Mode {
        Link.init(ctx)
        return when {
            !Link.isPaired -> Mode.NOT_PAIRED
            !Settings.keepConnected -> Mode.PAUSED
            else -> when (Link.state.phase) {
                Link.Phase.CONNECTED -> Mode.CONNECTED
                Link.Phase.OFFLINE -> Mode.OFFLINE
                else -> Mode.CONNECTING
            }
        }
    }

    fun macName(): String = Link.state.macName?.takeIf { it.isNotBlank() } ?: "Your Mac"

    fun stateText(m: Mode) = when (m) {
        Mode.CONNECTED -> "Connected"
        Mode.CONNECTING -> "Connecting…"
        Mode.OFFLINE -> "Offline"
        Mode.PAUSED -> "Paused"
        Mode.NOT_PAIRED -> "Not paired"
    }

    /** Same behaviour as the "Stay connected in the background" switch on Home. */
    fun setOn(ctx: Context, on: Boolean) {
        val app = ctx.applicationContext
        Link.init(app)
        if (on) { Settings.updateKeepConnected(true); LinkService.start(app) }
        else { Settings.updateKeepConnected(false); Link.stop(); app.stopService(Intent(app, LinkService::class.java)) }
        refreshAll(app)
    }

    fun toggle(ctx: Context) { Link.init(ctx); setOn(ctx, !Settings.keepConnected) }

    fun viewerIntent(ctx: Context): Intent =
        if (Link.isPaired) Intent(ctx, ViewerActivity::class.java) else Intent(ctx, MainActivity::class.java)

    fun refreshAll(ctx: Context) {
        val app = ctx.applicationContext
        runCatching { StatusWidget.update(app) }
        runCatching { TileService.requestListeningState(app, ComponentName(app, AndromacTile::class.java)) }
        runCatching { TileService.requestListeningState(app, ComponentName(app, MacScreenTile::class.java)) }
    }
}

class StatusWidget : android.appwidget.AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) { ids.forEach { render(ctx, mgr, it) } }
    override fun onAppWidgetOptionsChanged(ctx: Context, mgr: AppWidgetManager, id: Int, o: Bundle?) { render(ctx, mgr, id) }
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == ACTION_TOGGLE) {
            Settings.load(ctx.applicationContext)
            runCatching { Quick.toggle(ctx) }
        } else super.onReceive(ctx, i)
    }

    companion object {
        const val ACTION_TOGGLE = "app.andromac.WIDGET_TOGGLE"

        fun update(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            mgr.getAppWidgetIds(ComponentName(ctx, StatusWidget::class.java)).forEach { render(ctx, mgr, it) }
        }

        private fun render(ctx: Context, mgr: AppWidgetManager, id: Int) {
            val o = mgr.getAppWidgetOptions(id)
            val large = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) >= 180 &&
                o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) >= 150
            mgr.updateAppWidget(id, build(ctx, large))
        }

        fun build(ctx: Context, large: Boolean): RemoteViews {
            val mode = Quick.mode(ctx)
            val v = RemoteViews(ctx.packageName, if (large) R.layout.widget_large else R.layout.widget_small)
            val on = Settings.keepConnected
            val state = Quick.stateText(mode)
            val name = if (mode == Quick.Mode.NOT_PAIRED) "Andromac" else Quick.macName()
            v.setTextViewText(R.id.w_name, name)
            v.setTextViewText(R.id.w_state, state)
            v.setImageViewResource(R.id.w_dot, when (mode) {
                Quick.Mode.CONNECTED -> R.drawable.w_dot_green
                Quick.Mode.CONNECTING, Quick.Mode.OFFLINE -> R.drawable.w_dot_blue
                else -> R.drawable.w_dot_dim
            })
            v.setContentDescription(R.id.w_dot, state)
            v.setImageViewResource(R.id.w_toggle, if (on) R.drawable.ic_w_power_dark else R.drawable.ic_w_power_light)
            v.setInt(R.id.w_toggle, "setBackgroundResource", if (on) R.drawable.w_btn_on else R.drawable.w_btn_off)
            v.setContentDescription(R.id.w_toggle, if (on) "Andromac is on. Double tap to pause." else "Andromac is off. Double tap to turn on.")
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val toggle = Intent(ctx, StatusWidget::class.java).setAction(ACTION_TOGGLE)
            v.setOnClickPendingIntent(R.id.w_toggle, PendingIntent.getBroadcast(ctx, 11, toggle, flags))
            v.setOnClickPendingIntent(R.id.w_screen, PendingIntent.getActivity(ctx, 12, Quick.viewerIntent(ctx), flags))
            v.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(ctx, 13, Intent(ctx, MainActivity::class.java), flags))
            return v
        }
    }
}

class AndromacTile : TileService() {
    override fun onStartListening() = refresh()
    private fun refresh() {
        val t = qsTile ?: return
        val m = Quick.mode(this)
        t.state = when (m) { Quick.Mode.PAUSED, Quick.Mode.NOT_PAIRED -> Tile.STATE_INACTIVE; else -> Tile.STATE_ACTIVE }
        t.label = "Andromac"
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = when (m) {
            Quick.Mode.CONNECTED -> "Connected to ${Quick.macName()}"
            Quick.Mode.CONNECTING, Quick.Mode.OFFLINE -> "Connecting…"
            Quick.Mode.NOT_PAIRED -> "Not paired"
            Quick.Mode.PAUSED -> "Off"
        }
        t.updateTile()
    }
    override fun onClick() {
        if (Quick.mode(this) == Quick.Mode.NOT_PAIRED) { open(Intent(this, MainActivity::class.java)); return }
        Quick.toggle(this); refresh()
    }
    private fun open(i: Intent) = launch(this, i)
    companion object {
        fun launch(s: TileService, i: Intent) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) s.startActivityAndCollapse(
                PendingIntent.getActivity(s, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            else @Suppress("DEPRECATION") s.startActivityAndCollapse(i)
        }
    }
}

class MacScreenTile : TileService() {
    override fun onStartListening() {
        val t = qsTile ?: return
        t.label = "Mac screen"
        t.state = if (Link.run { init(this@MacScreenTile); isPaired }) Tile.STATE_INACTIVE else Tile.STATE_UNAVAILABLE
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = if (t.state == Tile.STATE_UNAVAILABLE) "Not paired" else "Open"
        t.updateTile()
    }
    override fun onClick() = AndromacTile.launch(this, Quick.viewerIntent(this))
}
