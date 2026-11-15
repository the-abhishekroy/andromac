package app.andromac

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.graphics.drawable.toBitmap
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

class NotifService : NotificationListenerService() {
    private val recent = LinkedHashMap<String, Long>()

    companion object {
        @Volatile var instance: NotifService? = null
        /** Latest notifications by key, so the Mac can reply to or open them. */
        private val keep = object : LinkedHashMap<String, Notification>(64, 0.75f, true) {
            override fun removeEldestEntry(e: MutableMap.MutableEntry<String, Notification>?) = size > 60
        }
        private val iconCache = HashMap<String, String>()
        private var sentEpoch = -1
        private val sentIcons = HashSet<String>()

        private fun replyAction(n: Notification): Notification.Action? =
            n.actions?.firstOrNull { it.remoteInputs?.isNotEmpty() == true }

        /** Type a reply into the app's own notification reply box (works for WhatsApp, Telegram, SMS, ...). */
        fun reply(ctx: Context, key: String, text: String): Boolean {
            val n = synchronized(keep) { keep[key] } ?: return false
            val act = replyAction(n) ?: return false
            return try {
                val ri = act.remoteInputs
                val intent = Intent(); val b = Bundle()
                ri.forEach { b.putCharSequence(it.resultKey, text) }
                android.app.RemoteInput.addResultsToIntent(ri, intent, b)
                act.actionIntent.send(ctx, 0, intent); true
            } catch (e: Exception) { false }
        }

        /** Open the conversation behind a notification (as if you tapped it). */
        fun open(ctx: Context, key: String, title: String): Boolean {
            val n = synchronized(keep) { keep[key] }
            val pi = n?.contentIntent
            if (pi != null) try {
                val opts = android.app.ActivityOptions.makeBasic().apply {
                    if (Build.VERSION.SDK_INT >= 34) setPendingIntentBackgroundActivityStartMode(android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                }
                pi.send(ctx, 0, null, null, null, null, opts.toBundle()); return true
            } catch (e: Exception) { /* background start blocked: fall through to tapping it in the shade */ }
            return ControlService.instance?.openNotification(title) ?: false
        }
    }

    private fun appIcon(pkg: String): String? {
        iconCache[pkg]?.let { return it }
        return runCatching {
            val bmp = packageManager.getApplicationIcon(pkg).toBitmap(96, 96)
            Badge.encode(bmp).also { iconCache[pkg] = it }
        }.getOrNull()
    }

    override fun onListenerConnected() { instance = this; Link.init(this); LinkService.start(this) }
    override fun onListenerDisconnected() { if (instance === this) instance = null }
    override fun onCreate() { super.onCreate(); Settings.load(this) }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName || !Settings.mirrorNotifications) return
        if (sbn.packageName in Settings.muted || sbn.packageName == "android") return
        val n = sbn.notification
        if (Settings.hideOngoing && n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (title.isEmpty() && text.isEmpty()) return
        // skip duplicates (apps re-post the same notification when updating progress etc.)
        val sig = "${sbn.key}|$title|$text"
        val now = System.currentTimeMillis()
        if (recent[sig]?.let { now - it < 5000 } == true) return
        recent[sig] = now
        if (recent.size > 200) recent.remove(recent.keys.first())

        val pm = packageManager
        val label = runCatching { pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString() }
            .getOrDefault(sbn.packageName)
        val data = JSONObject().put("id", sbn.id).put("key", sbn.key).put("pkg", sbn.packageName)
            .put("app", label).put("title", title).put("text", text)
            .put("sub", ex.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: "")
            .put("ts", sbn.postTime)
        Otp.extract("$title $text")?.let { data.put("otp", it) }
        synchronized(keep) { keep[sbn.key] = n }
        data.put("canReply", replyAction(n) != null)
        if (sentEpoch != Link.epoch) { sentEpoch = Link.epoch; sentIcons.clear() }
        if (sentIcons.add(sbn.packageName)) appIcon(sbn.packageName)?.let { data.put("icon", it) }
        Link.send("notification", data)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        Link.send("notification_dismiss", JSONObject().put("key", sbn.key))
    }
}
