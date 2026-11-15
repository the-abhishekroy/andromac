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

    private var file: java.io.File? = null

    /** History is kept in this app's private storage so it survives restarts, and is swapped with the Mac on every connect. */
    fun load(ctx: Context) {
        if (file != null) return
        file = java.io.File(ctx.filesDir, "clipboard.json")
        runCatching {
            val arr = org.json.JSONArray(file!!.readText())
            val loaded = (0 until arr.length()).map { arr.getJSONObject(it) }
                .map { Item(it.getString("t"), it.optBoolean("m"), it.optLong("d")) }.sortedByDescending { it.time }
            items.clear(); items.addAll(loaded)
        }
    }

    private fun save() {
        val f = file ?: return
        val arr = org.json.JSONArray(); items.forEach { arr.put(org.json.JSONObject().put("t", it.text).put("m", it.fromMac).put("d", it.time)) }
        runCatching { f.writeText(arr.toString()) }
    }

    fun add(text: String, fromMac: Boolean, time: Long = System.currentTimeMillis()) {
        if (text.isEmpty()) return
        items.removeAll { it.text == text }
        items.add(0, Item(text, fromMac, time))
        while (items.size > 100) items.removeAt(items.size - 1)
        save()
    }

    fun clear() { items.clear(); save() }

    /** Everything we have, for the Mac. */
    fun export(): org.json.JSONArray {
        val arr = org.json.JSONArray()
        items.take(100).filter { it.text.length < 20_000 }.forEach {
            arr.put(org.json.JSONObject().put("t", it.text).put("s", if (it.fromMac) "mac" else "phone").put("ts", it.time))
        }
        return arr
    }

    /** Merge the Mac's history into ours; if the Mac's newest item is newer than anything copied here, make it current. */
    fun merge(ctx: Context, arr: org.json.JSONArray?) {
        if (arr == null) return
        val lastLocal = items.firstOrNull { !it.fromMac }?.time ?: 0L
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val t = o.optString("t"); if (t.isEmpty() || items.any { it.text == t }) continue
            items.add(Item(t, fromMac = o.optString("s") != "phone", time = o.optLong("ts")))
        }
        val sorted = items.sortedByDescending { it.time }.take(100)
        items.clear(); items.addAll(sorted); save()
        val newest = items.firstOrNull()
        if (Settings.syncClipboard && newest != null && newest.fromMac && newest.time > lastLocal) applyFromMac(ctx, newest.text)
    }

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
