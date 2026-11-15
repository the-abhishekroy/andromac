package app.andromac

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/** Shows a notification that came from the Mac. */
object MacNotify {
    private var counter = 1000

    private val macIcons = HashMap<String, android.graphics.Bitmap>()

    fun show(ctx: Context, d: JSONObject) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("mac", "Mac", NotificationManager.IMPORTANCE_HIGH))
        val title = d.optString("title"); val text = d.optString("text"); val app = d.optString("app", "Mac")
        val bundle = d.optString("pkg")
        d.optString("icon").takeIf { it.isNotEmpty() }?.let { Badge.decode(it)?.let { b -> macIcons[bundle] = b } }
        val open = android.content.Intent(ctx, ViewerActivity::class.java)
            .putExtra("bundle", bundle).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        val pi = android.app.PendingIntent.getActivity(ctx, counter, open, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(ctx, "mac")
            .setSmallIcon(R.drawable.ic_stat)
            .setLargeIcon(Badge.withMacBadge(macIcons[bundle]))
            .setContentTitle(if (title.isEmpty()) app else title)
            .setContentText(text)
            .setSubText("$app · Mac")
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify(counter++, n)
    }

    /** The Mac asked to see this screen: Android needs an on-device tap, so we post an actionable notification. */
    fun askScreen(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("mac", "Mac", NotificationManager.IMPORTANCE_HIGH))
        val pi = android.app.PendingIntent.getActivity(ctx, 3,
            android.content.Intent(ctx, ScreenConsentActivity::class.java), android.app.PendingIntent.FLAG_IMMUTABLE)
        nm.notify(999, NotificationCompat.Builder(ctx, "mac").setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Your Mac wants to see this screen").setContentText("Tap to review and allow")
            .setContentIntent(pi).setAutoCancel(true).setFullScreenIntent(pi, true).build())
    }

    /** Control was requested but the accessibility service is off: Android requires the user to switch it on. */
    fun askAccessibility(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("mac", "Mac", NotificationManager.IMPORTANCE_HIGH))
        val pi = android.app.PendingIntent.getActivity(ctx, 4,
            android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS), android.app.PendingIntent.FLAG_IMMUTABLE)
        nm.notify(998, NotificationCompat.Builder(ctx, "mac").setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Turn on Andromac to let your Mac control this phone")
            .setContentText("Tap, then switch on Andromac under Accessibility (if greyed out: App info → ⋮ → Allow restricted settings)")
            .setContentIntent(pi).setAutoCancel(true).build())
    }
}
