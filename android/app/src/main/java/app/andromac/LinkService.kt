package app.andromac

import android.app.*
import android.content.*
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.content.ClipboardManager

class LinkService : Service() {
    override fun onBind(i: Intent?): IBinder? = null

    private fun build(): Notification {
        val st = Link.state
        val paused = !Settings.keepConnected
        val text = if (paused) "Paused" else when (st.phase) {
            Link.Phase.CONNECTED -> "Connected to ${st.macName ?: "your Mac"}"
            Link.Phase.CONNECTING -> "Connecting…"
            Link.Phase.OFFLINE -> "Mac not reachable — retrying"
            Link.Phase.NOT_PAIRED -> "Not paired"
        }
        val fl = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val toggle = PendingIntent.getForegroundService(this, 21, Intent(this, LinkService::class.java).setAction(if (paused) ACTION_RESUME else ACTION_PAUSE),
            fl)
        val screen = PendingIntent.getActivity(this, 22, Quick.viewerIntent(this), fl)
        return NotificationCompat.Builder(this, "link")
            .addAction(0, if (paused) "Resume" else "Pause", toggle)
            .addAction(0, "Mac screen", screen)
            .setSmallIcon(R.drawable.ic_stat).setContentTitle("Andromac").setContentText(text)
            .setOngoing(true).setPriority(NotificationCompat.PRIORITY_MIN).setOnlyAlertOnce(true)
            .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
            .build()
    }

    private var clipListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Settings.load(this)
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("link", "Connection status", NotificationManager.IMPORTANCE_MIN))
        // Android requires startForeground() right after startForegroundService(), even if we are about to stop:
        // quitting first crashes the whole app ("did not then call Service.startForeground()").
        if (intent?.action == ACTION_PAUSE) {
            // keep the (paused) notification so "Resume" stays reachable
            Link.init(this); Settings.updateKeepConnected(false); Link.stop()
            startForeground(1, build(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            Quick.refreshAll(this)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_RESUME) { Link.init(this); Settings.updateKeepConnected(true) }
        startForeground(1, build(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        if (!Settings.keepConnected) { Link.stop(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY }
        Link.init(this)
        Link.onState = { nm.notify(1, build()) }
        Link.start()
        watchClipboard()
        return START_STICKY
    }

    /** Phone → Mac clipboard in real time. Android hides clipboard contents from background apps, so when the
     *  change callback fires without readable text we briefly show a transparent window (needs "Display over other apps"). */
    private fun watchClipboard() {
        if (clipListener != null) return
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipListener = ClipboardManager.OnPrimaryClipChangedListener {
            if (!Settings.syncClipboard) return@OnPrimaryClipChangedListener
            // Android hides clipboard contents from background apps; what can be read is synced, the rest uses the Share action or tile.
            runCatching { ClipHistory.captureLocal(this, cm) }
        }
        cm.addPrimaryClipChangedListener(clipListener)
    }

    /** The user swiped the app away from recents: keep running as a service unless the switch is off. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (Settings.keepConnected) {
            val pi = PendingIntent.getForegroundService(this, 7, Intent(this, LinkService::class.java), PendingIntent.FLAG_IMMUTABLE)
            (getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(AlarmManager.ELAPSED_REALTIME, android.os.SystemClock.elapsedRealtime() + 1500, pi)
        }
    }

    override fun onDestroy() {
        clipListener?.let { (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).removePrimaryClipChangedListener(it) }
        clipListener = null
        super.onDestroy()
    }

    companion object {
        const val ACTION_PAUSE = "app.andromac.PAUSE"
        const val ACTION_RESUME = "app.andromac.RESUME"
        /** Starts the background connection, unless the user turned it off with the switch. */
        fun start(ctx: Context) {
            Settings.load(ctx)
            if (!Settings.keepConnected) return
            ContextCompat.startForegroundService(ctx, Intent(ctx, LinkService::class.java))
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) { Link.init(ctx); if (Link.pairingLink() != null && Settings.keepConnected) LinkService.start(ctx) }
    }
}
