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

    private data class AppInfoLite(val label: String, val iconB64: String?)
    private val infoCache = HashMap<String, AppInfoLite>()

    /** "com.snapchat.android" -> "Snapchat": a readable name when Android won't tell us the real one. */
    private fun friendlyName(pkg: String): String {
        val skip = setOf("com", "org", "net", "in", "io", "android", "app", "apps", "google", "mobile", "messenger")
        val part = pkg.split('.').lastOrNull { it !in skip && it.length > 2 } ?: pkg.substringAfterLast('.')
        return part.replaceFirstChar { it.uppercase() }
    }

    /**
     * Name and icon of the app behind a notification. Apps in another profile (Secure Folder, work profile) are invisible to
     * PackageManager, so ask LauncherApps for that profile the way a launcher does, then fall back to a readable name.
     */
    private fun describe(sbn: StatusBarNotification): AppInfoLite {
        val pkg = sbn.packageName
        val ck = pkg + "@" + sbn.user.hashCode()
        infoCache[ck]?.let { return it }
        val pm = packageManager
        var label: String? = null
        var bmp: android.graphics.Bitmap? = null
        runCatching {
            val ai = pm.getApplicationInfo(pkg, 0)
            label = pm.getApplicationLabel(ai).toString(); bmp = pm.getApplicationIcon(ai).toBitmap(96, 96)
        }
        if (label == null || bmp == null) runCatching {
            val act = getSystemService(android.content.pm.LauncherApps::class.java).getActivityList(pkg, sbn.user).firstOrNull()
            if (act != null) { if (label == null) label = act.label.toString(); if (bmp == null) bmp = act.getIcon(0).toBitmap(96, 96) }
        }
        if (bmp == null) runCatching {                    // last resort: the notification's own small icon on a dark tile
            val d = sbn.notification.smallIcon?.loadDrawable(this)
            if (d != null) {
                val tile = android.graphics.Bitmap.createBitmap(96, 96, android.graphics.Bitmap.Config.ARGB_8888)
                val c = android.graphics.Canvas(tile)
                c.drawRoundRect(android.graphics.RectF(0f, 0f, 96f, 96f), 22f, 22f, android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF1E1E1E.toInt() })
                d.setBounds(22, 22, 74, 74); d.setTint(0xFFFFFFFF.toInt()); d.draw(c); bmp = tile
            }
        }
        return AppInfoLite(label ?: friendlyName(pkg), bmp?.let { Badge.encode(it) }).also { infoCache[ck] = it }
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
        // housekeeping notices apps post while syncing ("Updating messages…", "Checking for new messages"): not worth mirroring
        if (Regex("^(updating|checking for new|syncing|refreshing|downloading new)\\b", RegexOption.IGNORE_CASE).containsMatchIn(title.trim()) ||
            Regex("^(updating|checking for new|syncing)\\b", RegexOption.IGNORE_CASE).containsMatchIn(text.trim())) return
        // skip duplicates (apps re-post the same notification when updating progress etc.)
        val sig = "${sbn.key}|$title|$text"
        val now = System.currentTimeMillis()
        if (recent[sig]?.let { now - it < 5000 } == true) return
        recent[sig] = now
        if (recent.size > 200) recent.remove(recent.keys.first())

        val info = describe(sbn)
        val label = info.label
        val data = JSONObject().put("id", sbn.id).put("key", sbn.key).put("pkg", sbn.packageName)
            .put("app", label).put("title", title).put("text", text)
            .put("sub", ex.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: "")
            .put("ts", sbn.postTime)
        Otp.extract("$title $text")?.let { data.put("otp", it) }
        synchronized(keep) { keep[sbn.key] = n }
        data.put("canReply", replyAction(n) != null)
        if (sentEpoch != Link.epoch) { sentEpoch = Link.epoch; sentIcons.clear() }
        if (sentIcons.add(sbn.packageName)) info.iconB64?.let { data.put("icon", it) }
        Link.send("notification", data)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        Link.send("notification_dismiss", JSONObject().put("key", sbn.key))
    }
}
