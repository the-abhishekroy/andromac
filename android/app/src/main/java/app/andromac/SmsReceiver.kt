package app.andromac

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        Link.init(ctx)
        if (!Settings.forwardSms) return
        LinkService.start(ctx)
        val body = parts.joinToString("") { it.messageBody ?: "" }
        val data = JSONObject().put("from", parts[0].originatingAddress ?: "")
            .put("body", body).put("ts", parts[0].timestampMillis)
        Otp.extract(body)?.let { data.put("otp", it) }
        // the service may still be connecting; retry briefly
        val pending = goAsync()
        Thread {
            repeat(20) { if (Link.send("sms", data)) { pending.finish(); return@Thread }; Thread.sleep(500) }
            pending.finish()
        }.start()
    }
}
