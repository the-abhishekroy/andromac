package app.andromac

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Base64
import androidx.compose.runtime.mutableStateListOf
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Clipboard history (text, links and images), saved in this app's private storage and swapped with the Mac
 * every time they connect. The phone's own system clipboard history (Samsung / Gboard) is not readable by apps,
 * but everything Andromac puts on the clipboard also lands there.
 */
object ClipHistory {
    data class Item(val text: String, val fromMac: Boolean, val time: Long = System.currentTimeMillis(),
                    val image: ByteArray? = null, val mime: String? = null) {
        val hash: String get() = if (image != null) ImageCodec.sha(image) else text
        val key: String get() = if (image != null) "img:" + ImageCodec.sha(image) else text
    }
    val items = mutableStateListOf<Item>()
    @Volatile private var ignoreText: String? = null
    @Volatile private var ignoreHash: String? = null
    private var dir: File? = null
    private const val MAX_ITEMS = 100
    private const val MAX_IMAGES = 30

    private fun ext(mime: String?) = if (mime == "image/png") "png" else "jpg"

    fun load(ctx: Context) {
        if (dir != null) return
        dir = File(ctx.filesDir, "clips").also { it.mkdirs() }
        runCatching {
            val arr = JSONArray(File(ctx.filesDir, "clipboard.json").readText())
            val loaded = (0 until arr.length()).map { arr.getJSONObject(it) }.mapNotNull { o ->
                val f = o.optString("f")
                if (f.isNotEmpty()) {
                    val bytes = runCatching { File(dir, f).readBytes() }.getOrNull() ?: return@mapNotNull null
                    Item("", o.optBoolean("m"), o.optLong("d"), bytes, o.optString("mt").ifEmpty { "image/jpeg" })
                } else Item(o.getString("t"), o.optBoolean("m"), o.optLong("d"))
            }.sortedByDescending { it.time }
            items.clear(); items.addAll(loaded)
        }
    }

    private fun save(ctx: Context?) {
        val d = dir ?: return
        val arr = JSONArray(); val keep = HashSet<String>()
        items.forEach {
            if (it.image != null) {
                val name = ImageCodec.sha(it.image) + "." + ext(it.mime); keep.add(name)
                val f = File(d, name); if (!f.exists()) runCatching { f.writeBytes(it.image) }
                arr.put(JSONObject().put("f", name).put("mt", it.mime).put("m", it.fromMac).put("d", it.time))
            } else arr.put(JSONObject().put("t", it.text).put("m", it.fromMac).put("d", it.time))
        }
        d.listFiles()?.filter { it.name !in keep }?.forEach { it.delete() }
        val ctxFiles = d.parentFile ?: return
        runCatching { File(ctxFiles, "clipboard.json").writeText(arr.toString()) }
    }

    private fun trim() {
        while (items.size > MAX_ITEMS) items.removeAt(items.size - 1)
        var images = 0
        val it = items.iterator()
        while (it.hasNext()) { val x = it.next(); if (x.image != null && ++images > MAX_IMAGES) it.remove() }
    }

    fun add(text: String, fromMac: Boolean, time: Long = System.currentTimeMillis()) {
        if (text.isEmpty()) return
        items.removeAll { it.text == text && it.image == null }
        items.add(0, Item(text, fromMac, time)); trim(); save(null)
    }

    fun addImage(bytes: ByteArray, mime: String, fromMac: Boolean, time: Long = System.currentTimeMillis()) {
        val h = ImageCodec.sha(bytes)
        items.removeAll { it.image != null && ImageCodec.sha(it.image) == h }
        items.add(0, Item("", fromMac, time, bytes, mime)); trim(); save(null)
    }

    fun clear() { items.clear(); save(null) }

    // ----- Mac -> phone: put things on this phone's clipboard (they also appear in Gboard / Samsung clipboard history) -----
    fun applyFromMac(ctx: Context, text: String) {
        ignoreText = text
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("Andromac", text))
        add(text, fromMac = true)
    }

    fun applyImageFromMac(ctx: Context, bytes: ByteArray, mime: String) {
        val h = ImageCodec.sha(bytes); ignoreHash = h
        val f = File(File(ctx.cacheDir, "clip-images").apply { mkdirs() }, "$h.${ext(mime)}"); f.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(ctx, "app.andromac.fileprovider", f)
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newUri(ctx.contentResolver, "Andromac", uri))
        addImage(bytes, mime, fromMac = true)
    }

    // ----- phone -> Mac -----
    /** Reads what was just copied on this phone (text, link or image), records it and sends it. Returns false if it could not be read. */
    fun captureLocal(ctx: Context, cm: ClipboardManager): Boolean {
        val desc = cm.primaryClipDescription ?: return false
        val clip = cm.primaryClip ?: return false
        if (clip.itemCount == 0) return false
        val item = clip.getItemAt(0)
        if (desc.hasMimeType("image/*") && item.uri != null) {
            val raw = ImageCodec.readUri(ctx, item.uri) ?: return false
            val (bytes, mime) = ImageCodec.prepare(raw) ?: return false
            val h = ImageCodec.sha(bytes)
            if (ignoreHash == h) { ignoreHash = null; return true }
            if (items.firstOrNull()?.let { it.image != null && it.hash == h } == true) return true
            addImage(bytes, mime, fromMac = false)
            if (Settings.syncClipboard) Link.send("clipboard", JSONObject().put("image", Base64.encodeToString(bytes, Base64.NO_WRAP)).put("mime", mime).put("ts", System.currentTimeMillis()))
            return true
        }
        val text = item.coerceToText(ctx)?.toString()
        if (text.isNullOrEmpty()) return false
        onLocalChange(text)?.let { if (Settings.syncClipboard) Link.send("clipboard", JSONObject().put("text", it).put("ts", System.currentTimeMillis())) }
        return true
    }

    /** Called when the phone's clipboard changed. Returns the text to send, or null if it should be ignored. */
    fun onLocalChange(text: String?): String? {
        if (text.isNullOrEmpty()) return null
        if (ignoreText == text) { ignoreText = null; return null }
        if (items.firstOrNull()?.let { it.image == null && it.text == text } == true) return null
        add(text, fromMac = false)
        return text
    }

    fun recopy(ctx: Context, item: Item) {
        if (item.image != null) {
            applyImageFromMac(ctx, item.image, item.mime ?: "image/jpeg")
            if (Settings.syncClipboard) Link.send("clipboard", JSONObject().put("image", Base64.encodeToString(item.image, Base64.NO_WRAP)).put("mime", item.mime).put("ts", System.currentTimeMillis()))
        } else {
            applyFromMac(ctx, item.text)
            if (Settings.syncClipboard) Link.send("clipboard", JSONObject().put("text", item.text).put("ts", System.currentTimeMillis()))
        }
    }

    // ----- exchange everything on connect -----
    fun export(): JSONArray {
        val arr = JSONArray()
        var images = 0
        var budget = 6_000_000          // keep the sync message small so it can never choke the link
        items.take(MAX_ITEMS).forEach {
            val o = JSONObject().put("s", if (it.fromMac) "mac" else "phone").put("ts", it.time)
            if (it.image != null) { if (++images > 10 || it.image.size > budget) return@forEach; budget -= it.image.size; o.put("img", Base64.encodeToString(it.image, Base64.NO_WRAP)).put("mime", it.mime) }
            else if (it.text.length < 20_000) o.put("t", it.text) else return@forEach
            arr.put(o)
        }
        return arr
    }

    /** Merge the Mac's history into ours; if the Mac's newest item is newer than anything copied here, make it current. */
    fun merge(ctx: Context, arr: JSONArray?) {
        if (arr == null) return
        val lastLocal = items.firstOrNull { !it.fromMac }?.time ?: 0L
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val fromMac = o.optString("s") != "phone"; val ts = o.optLong("ts")
            val img = o.optString("img")
            if (img.isNotEmpty()) {
                val bytes = runCatching { Base64.decode(img, Base64.DEFAULT) }.getOrNull() ?: continue
                val h = ImageCodec.sha(bytes)
                if (items.any { it.image != null && ImageCodec.sha(it.image) == h }) continue
                items.add(Item("", fromMac, ts, bytes, o.optString("mime").ifEmpty { "image/jpeg" }))
            } else {
                val t = o.optString("t"); if (t.isEmpty() || items.any { it.image == null && it.text == t }) continue
                items.add(Item(t, fromMac, ts))
            }
        }
        val sorted = items.sortedByDescending { it.time }
        items.clear(); items.addAll(sorted); trim(); save(null)
        val newest = items.firstOrNull()
        if (Settings.syncClipboard && newest != null && newest.fromMac && newest.time > lastLocal) {
            if (newest.image != null) applyImageFromMac(ctx, newest.image, newest.mime ?: "image/jpeg") else applyFromMac(ctx, newest.text)
        }
    }
}
