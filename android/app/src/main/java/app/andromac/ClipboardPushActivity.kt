package app.andromac

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import org.json.JSONObject

class ClipboardPushActivity : Activity() {
    private var done = false
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || done) return
        done = true
        Link.init(this)
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        runCatching { ClipHistory.captureLocal(this, cm) }
        finish()
    }
}

class ShareActivity : Activity() {
    override fun onCreate(b: android.os.Bundle?) {
        super.onCreate(b)
        Link.init(this)
        val text = intent.getStringExtra(android.content.Intent.EXTRA_TEXT)
        val ok = !text.isNullOrEmpty() &&
            Link.send("clipboard", JSONObject().put("text", text).put("ts", System.currentTimeMillis()))
        Toast.makeText(this, if (ok) "Sent to Mac" else "Not connected", Toast.LENGTH_SHORT).show()
        finish()
    }
}
