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
        val text = when (st.phase) {
            Link.Phase.CONNECTED -> "Connected to ${st.macName ?: "your Mac"}"
            Link.Phase.CONNECTING -> "Connecting…"
            Link.Phase.OFFLINE -> "Mac not reachable — retrying"
            Link.Phase.NOT_PAIRED -> "Not paired"
        }
        return NotificationCompat.Builder(this, "link")
            .setSmallIcon(R.drawable.ic_stat).setContentTitle("Andromac").setContentText(text)
            .setOngoing(true).setPriority(NotificationCompat.PRIORITY_MIN).setOnlyAlertOnce(true)
            .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
            .build()
    }

    private var clipListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Settings.load(this)
        if (!Settings.keepConnected) { Link.stop(); stopSelf(); return START_NOT_STICKY }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("link", "Connection status", NotificationManager.IMPORTANCE_MIN))
        startForeground(1, build(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
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
            val text = runCatching { cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString() }.getOrNull()
            if (text.isNullOrEmpty()) {
                if (android.provider.Settings.canDrawOverlays(this))
                    runCatching { startActivity(Intent(this, ClipboardPushActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)) }
            } else ClipHistory.onLocalChange(text)?.let {
                Link.send("clipboard", org.json.JSONObject().put("text", it).put("ts", System.currentTimeMillis()))
            }
        }
        cm.addPrimaryClipChangedListener(clipListener)
    }

    override fun onDestroy() {
        clipListener?.let { (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).removePrimaryClipChangedListener(it) }
        clipListener = null
        super.onDestroy()
    }

    companion object {
        fun start(ctx: Context) = ContextCompat.startForegroundService(ctx, Intent(ctx, LinkService::class.java))
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) { Link.init(ctx); if (Link.pairingLink() != null && Settings.keepConnected) LinkService.start(ctx) }
    }
}
