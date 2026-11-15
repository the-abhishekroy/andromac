package app.andromac

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.runtime.mutableStateListOf

/** In-memory clipboard history (not written to disk: clipboards often hold secrets). */
object ClipHistory {
    data class Item(val text: String, val fromMac: Boolean, val time: Long = System.currentTimeMillis())
    val items = mutableStateListOf<Item>()
    @Volatile private var ignoreNext: String? = null

    fun add(text: String, fromMac: Boolean) {
        if (text.isEmpty()) return
        items.removeAll { it.text == text }
        items.add(0, Item(text, fromMac))
        while (items.size > 60) items.removeAt(items.size - 1)
    }

    fun clear() = items.clear()

    /** A Mac clipboard item arrived: put it on the phone's clipboard (shows up in Gboard / Samsung clipboard history). */
    fun applyFromMac(ctx: Context, text: String) {
        ignoreNext = text
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("Andromac", text))
        add(text, fromMac = true)
    }

    /** Called when the phone's clipboard changed. Returns the text to send, or null if it should be ignored. */
    fun onLocalChange(text: String?): String? {
        if (text.isNullOrEmpty()) return null
        if (ignoreNext == text) { ignoreNext = null; return null }
        if (items.firstOrNull()?.text == text) return null
        add(text, fromMac = false)
        return text
    }

    /** Re-copy an item from the history to both devices. */
    fun recopy(ctx: Context, item: Item) {
        applyFromMac(ctx, item.text)
        if (Settings.syncClipboard) Link.send("clipboard", org.json.JSONObject().put("text", item.text).put("ts", System.currentTimeMillis()))
    }
}
