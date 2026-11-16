package app.andromac

import android.content.ClipData
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import okhttp3.*
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.min

/** Single connection to the Mac, shared by every service. Reconnects with backoff. */
object Link {
    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    private var channel: Channel? = null
    private var sendSeq = 0
    private var lastSeq = 0
    private var backoff = 1000L
    private var running = false
    enum class Phase { NOT_PAIRED, CONNECTING, CONNECTED, OFFLINE }
    data class State(val phase: Phase = Phase.NOT_PAIRED, val macName: String? = null, val detail: String = "")

    var state by androidx.compose.runtime.mutableStateOf(State())
        private set
    var onState: ((State) -> Unit)? = null
    @Volatile private var controlWarned = false
    @Volatile var epoch = 0
    var macUser by androidx.compose.runtime.mutableStateOf("")
    @Volatile var videoSink: ((Int, ByteArray) -> Unit)? = null
    @Volatile var macScreen: ((String, JSONObject) -> Unit)? = null

    fun secretBytes(): ByteArray? = pairingLink()?.let { runCatching { Channel.decodeSecret(Uri.parse(it).lastPathSegment!!) }.getOrNull() }?.takeIf { it.size == 32 }

    /** What the Mac needs to know about file sharing from this phone. */
    fun filesState(): JSONObject = JSONObject().put("enabled", Settings.fileShare && FileServer.hasAllFilesAccess())
        .put("write", Settings.fileWrite).put("needsPermission", Settings.fileShare && !FileServer.hasAllFilesAccess())

    /** Start or stop the file server to match the settings, and tell the Mac. */
    fun applyFiles(ctx: Context) {
        val want = Settings.fileShare && FileServer.hasAllFilesAccess()
        val sec = secretBytes()
        if (want && sec != null) {
            runCatching { FileServer.start(ctx, sec) }
            Net.serveFiles()
        } else FileServer.stop()
        send("files_state", filesState())
    }

    fun init(ctx: Context) {
        app = ctx.applicationContext; Settings.load(app); ClipHistory.load(app)
        if (state.phase == Phase.NOT_PAIRED && pairingLink() != null) state = State(Phase.CONNECTING)
    }
    fun unpair() { prefs().edit().remove("link").apply(); socket?.cancel(); socket = null; running = false; pushState(State(Phase.NOT_PAIRED)) }
    val isPaired get() = pairingLink() != null

    private fun prefs() = app.getSharedPreferences("andromac", Context.MODE_PRIVATE)
    fun pairingLink(): String? = prefs().getString("link", null)
    fun savePairing(link: String) { prefs().edit().putString("link", link).apply() }

    private fun pushState(s: State) { main.post { state = s; onState?.invoke(s); Quick.refreshAll(app) } }

    fun start() {
        if (running) return
        running = true
        connect()
    }

    fun stopNow() = stop()
    fun stop() { running = false; socket?.cancel(); socket = null; pushState(State(Phase.OFFLINE)) }

    fun restart() {
        if (!Settings.keepConnected) return
        socket?.cancel(); socket = null; running = true; backoff = 1000; connect()
    }

    private fun connect() {
        if (!running) return
        val uri = pairingLink()?.let { runCatching { Uri.parse(it) }.getOrNull() }
        val secret = uri?.lastPathSegment?.let { runCatching { Channel.decodeSecret(it) }.getOrNull() }
        if (uri == null || uri.host == null || secret == null || secret.size != 32) {
            pushState(State(Phase.NOT_PAIRED)); return
        }
        channel = Channel(secret)
        sendSeq = 0; lastSeq = 0
        pushState(State(Phase.CONNECTING, state.macName))
        val remotePort = if (uri.port > 0) uri.port else 8765
        Net.start(app)
        val local = Net.proxy(uri.host!!, remotePort)
        if (local == null) {   // built-in Tailscale not signed in / not up yet; Net calls restart() when it is
            pushState(State(Phase.CONNECTING, state.macName, if (Net.state == "login") "Sign in to Tailscale" else "Starting secure connection"))
            return
        }
        Net.ensureBridge(uri.host!!)
        val req = Request.Builder().url("ws://127.0.0.1:$local/").build()
        socket = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                backoff = 1000
                epoch++
                pushState(State(Phase.CONNECTED, state.macName))
                if (Settings.syncClipboard) send("clip_sync", JSONObject().put("items", ClipHistory.export()))
                send("hello", JSONObject().put("device", android.os.Build.MODEL).put("version", 1).put("tip", Net.ip ?: "").put("files", filesState()))
                applyFiles(app)
                sendBattery()
            }
            override fun onMessage(ws: WebSocket, bytes: ByteString) { handle(bytes.toByteArray()) }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = retry(ws, t.message)
            override fun onClosed(ws: WebSocket, code: Int, reason: String) = retry(ws, "closed")
        })
    }

    private fun retry(ws: WebSocket, why: String?) {
        if (ws !== socket) return
        android.util.Log.w("AndromacLink", "connection ended: $why")
        socket = null
        if (!running) return
        pushState(State(Phase.OFFLINE, state.macName, "Retrying in ${backoff / 1000}s"))
        main.postDelayed({ connect() }, backoff)
        backoff = min(backoff * 2, 30_000)
    }

    @Synchronized
    fun send(type: String, data: JSONObject): Boolean {
        val ws = socket ?: return false
        val ch = channel ?: return false
        sendSeq++
        val env = JSONObject().put("seq", sendSeq).put("type", type)
            .put("ts", System.currentTimeMillis()).put("data", data)
        return ws.send(ch.seal(env.toString().toByteArray()).toByteString())
    }

    fun queuedBytes(): Long = socket?.queueSize() ?: 0L

    /** Binary video packet: [1][flags][H.264 access unit]. flags bit0 = keyframe. */
    fun sendVideo(flags: Int, au: ByteArray): Boolean {
        val ws = socket ?: return false
        val ch = channel ?: return false
        return ws.send(ch.seal(byteArrayOf(1, flags.toByte()) + au).toByteString())
    }

    private fun handle(frame: ByteArray) {
        val plain = channel?.open(frame) ?: run { socket?.cancel(); return }
        if (plain.size > 2 && plain[0] == 1.toByte()) { videoSink?.invoke(plain[1].toInt(), plain.copyOfRange(2, plain.size)); return }
        val env = runCatching { JSONObject(String(plain)) }.getOrNull() ?: return
        val seq = env.optInt("seq"); if (seq <= lastSeq) return
        lastSeq = seq
        val data = env.optJSONObject("data") ?: JSONObject()
        when (env.optString("type")) {
            "clipboard" -> main.post {
                if (Settings.syncClipboard) {
                    val img = data.optString("image")
                    if (img.isNotEmpty()) runCatching { ClipHistory.applyImageFromMac(app, android.util.Base64.decode(img, android.util.Base64.DEFAULT), data.optString("mime").ifEmpty { "image/jpeg" }) }
                    else ClipHistory.applyFromMac(app, data.optString("text"))
                }
            }
            "hello" -> { macUser = data.optString("user"); pushState(state.copy(macName = data.optString("device"))) }
            "notification" -> if (Settings.showMacNotifications) MacNotify.show(app, data)
            "screen_request" -> if (!ScreenShareState.active) MacNotify.askScreen(app)
            "keyframe" -> ScreenShareState.requestKeyframe?.invoke()
            "screen_stop" -> ScreenShareState.stop(app)
            "input" -> if (data.optString("target") != "mac") {
                if (ControlService.instance == null) {
                    // Android only lets the user switch the accessibility service on: tell both sides instead of silently ignoring taps
                    if (!controlWarned) { controlWarned = true; send("control_off", JSONObject()); MacNotify.askAccessibility(app) }
                } else { controlWarned = false; ControlService.handle(data) }
            }
            "mac_screen_started", "mac_screen_denied", "mac_screen_stopped", "cursor" -> macScreen?.invoke(env.optString("type"), data)
            "clip_sync" -> main.post { if (Settings.syncClipboard) ClipHistory.merge(app, data.optJSONArray("items")) }
            "notification_reply" -> NotifService.reply(app, data.optString("key"), data.optString("text"))
            "notification_open" -> NotifService.open(app, data.optString("key"), data.optString("title"))
            "ping" -> send("pong", JSONObject())
        }
    }

    fun sendBattery() {
        val i = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100 / i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        send("battery", JSONObject().put("level", level)
            .put("charging", st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL))
    }
}
