package app.andromac

import android.content.Context
import android.os.Environment
import android.os.storage.StorageManager
import java.io.*
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

/**
 * A small WebDAV server that shows this phone's storage to the paired Mac (Finder: "Connect to Server").
 * It listens on 127.0.0.1 only and is reached through the private network; every request needs the key derived from the QR pairing.
 *
 *   /Phone/                  -> "Internal storage" and "SD card"
 *   /Phone/Internal storage/ -> /storage/emulated/0
 */
object FileServer {
    const val PORT = 8790
    private var socket: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool()
    @Volatile private var password = ""

    fun isRunning() = socket?.isClosed == false

    fun hasAllFilesAccess(): Boolean = Environment.isExternalStorageManager()

    fun start(ctx: Context, secret: ByteArray) {
        password = davPassword(secret)
        if (isRunning()) return
        val s = ServerSocket(PORT, 16, InetAddress.getByName("127.0.0.1"))
        socket = s
        Thread({
            while (!s.isClosed) {
                val c = try { s.accept() } catch (e: Exception) { break }
                pool.execute { runCatching { handle(ctx, c) }; runCatching { c.close() } }
            }
        }, "andromac-files").start()
    }

    fun stop() { runCatching { socket?.close() }; socket = null }

    /** Same derivation as the Mac: HKDF-SHA256(secret, salt "andromac-v1", info "webdav"), first 24 chars of base64url. */
    fun davPassword(secret: ByteArray): String {
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        fun h(k: ByteArray, d: ByteArray): ByteArray { mac.init(javax.crypto.spec.SecretKeySpec(k, "HmacSHA256")); return mac.doFinal(d) }
        val prk = h("andromac-v1".toByteArray(), secret)
        val okm = h(prk, "webdav".toByteArray() + byteArrayOf(1))
        return android.util.Base64.encodeToString(okm, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP).take(24)
    }

    // ---------- storage roots ----------
    private fun roots(ctx: Context): LinkedHashMap<String, File> {
        val m = LinkedHashMap<String, File>()
        m["Internal storage"] = Environment.getExternalStorageDirectory()
        val sm = ctx.getSystemService(StorageManager::class.java)
        sm.storageVolumes.filter { !it.isPrimary && it.state == Environment.MEDIA_MOUNTED }.forEach { v ->
            v.directory?.let { m[if (m.containsKey("SD card")) "SD card " + (m.size) else "SD card"] = it }
        }
        return m
    }

    /** Map a URL path under /Phone to a file, or null if it escapes the storage roots. */
    private fun resolve(ctx: Context, path: String): File? {
        val parts = path.trim('/').split('/').filter { it.isNotEmpty() }
        if (parts.isEmpty() || parts[0] != "Phone") return null
        if (parts.size == 1) return File("/")                     // virtual root
        val base = roots(ctx)[parts[1]] ?: return null
        var f = base
        for (p in parts.drop(2)) { if (p == ".." || p.contains('/')) return null; f = File(f, p) }
        val canon = f.canonicalFile
        return if (canon.path.startsWith(base.canonicalPath)) canon else null
    }

    // ---------- HTTP ----------
    private class Req(val method: String, val path: String, val headers: Map<String, String>, val input: InputStream)

    private fun readLine(i: InputStream): String? {
        val b = StringBuilder()
        while (true) { val c = i.read(); if (c < 0) return if (b.isEmpty()) null else b.toString(); if (c == '\n'.code) break; if (c != '\r'.code) b.append(c.toChar()) }
        return b.toString()
    }

    private fun handle(ctx: Context, sock: Socket) {
        sock.soTimeout = 30_000
        val input = BufferedInputStream(sock.getInputStream()); val out = BufferedOutputStream(sock.getOutputStream())
        while (true) {
            val line = readLine(input) ?: return
            val sp = line.split(' '); if (sp.size < 2) return
            val headers = HashMap<String, String>()
            while (true) { val h = readLine(input) ?: return; if (h.isEmpty()) break; val i = h.indexOf(':'); if (i > 0) headers[h.substring(0, i).trim().lowercase()] = h.substring(i + 1).trim() }
            val raw = sp[1].substringBefore('?')
            val path = URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8")
            val req = Req(sp[0].uppercase(), path, headers, input)
            val keep = headers["connection"]?.lowercase() != "close"
            try { dispatch(ctx, req, out) } catch (e: Exception) { respond(out, 500, "Internal error", ""); return }
            out.flush()
            if (!keep) return
        }
    }

    private fun authorized(req: Req): Boolean {
        val a = req.headers["authorization"] ?: return false
        if (!a.startsWith("Basic ", true)) return false
        val dec = runCatching { String(android.util.Base64.decode(a.substring(6).trim(), android.util.Base64.DEFAULT)) }.getOrNull() ?: return false
        return MessageDigest.isEqual(dec.substringAfter(':').toByteArray(), password.toByteArray())
    }

    private fun respond(out: OutputStream, code: Int, msg: String, body: String, extra: String = "", type: String = "text/plain; charset=utf-8") {
        val b = body.toByteArray()
        out.write("HTTP/1.1 $code $msg\r\nContent-Type: $type\r\nContent-Length: ${b.size}\r\n$extra\r\n".toByteArray()); out.write(b)
    }

    private fun drain(req: Req) {                     // consume a request body we do not use
        val n = req.headers["content-length"]?.toLongOrNull() ?: 0; var left = n; val buf = ByteArray(8192)
        while (left > 0) { val r = req.input.read(buf, 0, minOf(left, buf.size.toLong()).toInt()); if (r < 0) break; left -= r }
    }

    private fun dispatch(ctx: Context, req: Req, out: OutputStream) {
        if (!authorized(req)) { drain(req); return respond(out, 401, "Unauthorized", "Andromac", "WWW-Authenticate: Basic realm=\"Andromac Phone\"\r\n") }
        if (!hasAllFilesAccess()) { drain(req); return respond(out, 503, "Allow All files access for Andromac on the phone", "") }
        val rw = Settings.fileWrite
        val dav = if (rw) "1, 2" else "1"
        when (req.method) {
            "OPTIONS" -> respond(out, 200, "OK", "", "DAV: $dav\r\nAllow: OPTIONS, PROPFIND, GET, HEAD${if (rw) ", PUT, MKCOL, DELETE, MOVE, COPY, LOCK, UNLOCK, PROPPATCH" else ""}\r\nMS-Author-Via: DAV\r\n")
            "PROPFIND" -> propfind(ctx, req, out)
            "GET", "HEAD" -> get(ctx, req, out)
            "LOCK" -> if (rw) { drain(req); val tok = "opaquelocktoken:" + UUID.randomUUID()
                respond(out, 200, "OK", "<?xml version=\"1.0\"?><D:prop xmlns:D=\"DAV:\"><D:lockdiscovery><D:activelock><D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope><D:depth>0</D:depth><D:timeout>Second-3600</D:timeout><D:locktoken><D:href>$tok</D:href></D:locktoken></D:activelock></D:lockdiscovery></D:prop>",
                    "Lock-Token: <$tok>\r\n", "application/xml; charset=utf-8") } else { drain(req); respond(out, 405, "Read-only", "") }
            "UNLOCK" -> { drain(req); respond(out, 204, "No Content", "") }
            "PROPPATCH" -> { drain(req); if (rw) respond(out, 207, "Multi-Status", "<?xml version=\"1.0\"?><D:multistatus xmlns:D=\"DAV:\"/>", "", "application/xml") else respond(out, 405, "Read-only", "") }
            "PUT" -> if (rw) put(ctx, req, out) else { drain(req); respond(out, 405, "Read-only", "") }
            "MKCOL" -> { drain(req); if (!rw) return respond(out, 405, "Read-only", "")
                val f = resolve(ctx, req.path); if (f == null || f.path == "/") respond(out, 403, "Forbidden", "") else if (f.exists()) respond(out, 405, "Exists", "") else if (f.mkdirs()) respond(out, 201, "Created", "") else respond(out, 409, "Conflict", "") }
            "DELETE" -> { drain(req); if (!rw) return respond(out, 405, "Read-only", "")
                val f = resolve(ctx, req.path); if (f == null || !f.exists() || f.path == "/" || isRootEntry(ctx, req.path)) respond(out, 404, "Not Found", "") else { f.deleteRecursively(); respond(out, 204, "No Content", "") } }
            "MOVE", "COPY" -> { drain(req); if (!rw) return respond(out, 405, "Read-only", ""); moveCopy(ctx, req, out) }
            else -> { drain(req); respond(out, 405, "Method Not Allowed", "") }
        }
    }

    private fun isRootEntry(ctx: Context, path: String) = path.trim('/').split('/').size <= 2

    private val httpDate = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US).apply { timeZone = TimeZone.getTimeZone("GMT") }
    private val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    private fun href(path: String, dir: Boolean): String {
        val enc = path.trim('/').split('/').filter { it.isNotEmpty() }.joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
        return "/" + enc + if (dir && enc.isNotEmpty()) "/" else ""
    }

    private fun entry(sb: StringBuilder, path: String, f: File?, name: String, dir: Boolean, root: File?) {
        sb.append("<D:response><D:href>").append(esc(href(path, dir))).append("</D:href><D:propstat><D:prop>")
        sb.append("<D:displayname>").append(esc(name)).append("</D:displayname>")
        sb.append(if (dir) "<D:resourcetype><D:collection/></D:resourcetype>" else "<D:resourcetype/>")
        if (f != null && f.path != "/") {
            sb.append("<D:getlastmodified>").append(httpDate.format(Date(f.lastModified()))).append("</D:getlastmodified>")
            sb.append("<D:creationdate>").append(isoDate.format(Date(f.lastModified()))).append("</D:creationdate>")
            if (!dir) { sb.append("<D:getcontentlength>").append(f.length()).append("</D:getcontentlength>")
                sb.append("<D:getcontenttype>").append(mime(f.name)).append("</D:getcontenttype>") }
        }
        val q = root ?: f
        if (dir && q != null && q.path != "/") { sb.append("<D:quota-available-bytes>").append(q.usableSpace).append("</D:quota-available-bytes><D:quota-used-bytes>").append(maxOf(0L, q.totalSpace - q.usableSpace)).append("</D:quota-used-bytes>") }
        sb.append("</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>")
    }

    private fun propfind(ctx: Context, req: Req, out: OutputStream) {
        drain(req)
        val depth = req.headers["depth"] ?: "1"
        val rts = roots(ctx)
        val parts = req.path.trim('/').split('/').filter { it.isNotEmpty() }
        val sb = StringBuilder("<?xml version=\"1.0\" encoding=\"utf-8\"?><D:multistatus xmlns:D=\"DAV:\">")
        if (parts.isEmpty()) { entry(sb, "/", null, "", true, null); if (depth != "0") entry(sb, "/Phone/", null, "Phone", true, null) }
        else if (parts[0] != "Phone") return respond(out, 404, "Not Found", "")
        else if (parts.size == 1) { entry(sb, "/Phone/", null, "Phone", true, null)
            if (depth != "0") rts.forEach { (n, f) -> entry(sb, "/Phone/$n/", f, n, true, f) } }
        else {
            val f = resolve(ctx, req.path) ?: return respond(out, 404, "Not Found", "")
            if (!f.exists()) return respond(out, 404, "Not Found", "")
            val root = rts[parts[1]]
            entry(sb, req.path, f, if (parts.size == 2) parts[1] else f.name, f.isDirectory, root)
            if (f.isDirectory && depth != "0") f.listFiles()?.sortedBy { it.name.lowercase() }?.forEach { c ->
                if (c.name.startsWith("._")) return@forEach
                entry(sb, req.path.trimEnd('/') + "/" + c.name, c, c.name, c.isDirectory, null)
            }
        }
        sb.append("</D:multistatus>")
        respond(out, 207, "Multi-Status", sb.toString(), "", "application/xml; charset=utf-8")
    }

    private fun get(ctx: Context, req: Req, out: OutputStream) {
        val f = resolve(ctx, req.path)
        if (f == null || !f.exists()) return respond(out, 404, "Not Found", "")
        if (f.isDirectory) return respond(out, 200, "OK", "Andromac phone folder", "", "text/plain")
        val len = f.length(); var start = 0L; var end = len - 1; var code = 200
        req.headers["range"]?.let { r -> Regex("bytes=(\\d*)-(\\d*)").find(r)?.let { m ->
            val a = m.groupValues[1]; val b = m.groupValues[2]
            if (a.isEmpty() && b.isNotEmpty()) { start = maxOf(0, len - b.toLong()) } else { if (a.isNotEmpty()) start = a.toLong(); if (b.isNotEmpty()) end = minOf(end, b.toLong()) }
            if (start in 0..end) code = 206 } }
        if (code == 206 && start > end) return respond(out, 416, "Range Not Satisfiable", "")
        val size = if (len == 0L) 0 else end - start + 1
        val hdr = "HTTP/1.1 $code ${if (code == 206) "Partial Content" else "OK"}\r\nContent-Type: ${mime(f.name)}\r\nContent-Length: $size\r\nAccept-Ranges: bytes\r\nLast-Modified: ${httpDate.format(Date(f.lastModified()))}\r\n" +
            (if (code == 206) "Content-Range: bytes $start-$end/$len\r\n" else "") + "\r\n"
        out.write(hdr.toByteArray())
        if (req.method == "GET" && size > 0) RandomAccessFile(f, "r").use { r -> r.seek(start); val buf = ByteArray(64 * 1024); var left = size
            while (left > 0) { val n = r.read(buf, 0, minOf(left, buf.size.toLong()).toInt()); if (n < 0) break; out.write(buf, 0, n); left -= n } }
    }

    private fun put(ctx: Context, req: Req, out: OutputStream) {
        val f = resolve(ctx, req.path)
        if (f == null || f.path == "/" || isRootEntry(ctx, req.path)) { drain(req); return respond(out, 403, "Forbidden", "") }
        f.parentFile?.mkdirs(); val existed = f.exists()
        val chunked = req.headers["transfer-encoding"]?.contains("chunked", true) == true
        FileOutputStream(f).use { fo ->
            if (chunked) while (true) { val sz = readLine(req.input)?.trim()?.substringBefore(';')?.toIntOrNull(16) ?: break
                if (sz == 0) { readLine(req.input); break }; val buf = ByteArray(sz); var o = 0; while (o < sz) { val r = req.input.read(buf, o, sz - o); if (r < 0) break; o += r }; fo.write(buf, 0, o); readLine(req.input) }
            else { var left = req.headers["content-length"]?.toLongOrNull() ?: 0; val buf = ByteArray(64 * 1024)
                while (left > 0) { val r = req.input.read(buf, 0, minOf(left, buf.size.toLong()).toInt()); if (r < 0) break; fo.write(buf, 0, r); left -= r } }
        }
        respond(out, if (existed) 204 else 201, if (existed) "No Content" else "Created", "")
    }

    private fun moveCopy(ctx: Context, req: Req, out: OutputStream) {
        val src = resolve(ctx, req.path)
        val destUrl = req.headers["destination"]?.let { URLDecoder.decode(it.replace("+", "%2B"), "UTF-8").substringAfter("://").substringAfter('/', "").let { p -> "/$p" } }
        val dst = destUrl?.let { resolve(ctx, it) }
        if (src == null || dst == null || !src.exists() || isRootEntry(ctx, req.path) || isRootEntry(ctx, destUrl)) return respond(out, 403, "Forbidden", "")
        val overwrite = req.headers["overwrite"]?.uppercase() != "F"; val existed = dst.exists()
        if (existed && !overwrite) return respond(out, 412, "Precondition Failed", "")
        if (existed) dst.deleteRecursively()
        dst.parentFile?.mkdirs()
        val ok = if (req.method == "MOVE") (src.renameTo(dst) || (src.copyRecursively(dst, true) && src.deleteRecursively())) else src.copyRecursively(dst, true)
        if (ok) respond(out, if (existed) 204 else 201, if (existed) "No Content" else "Created", "") else respond(out, 500, "Failed", "")
    }

    private fun mime(name: String) = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"
}
