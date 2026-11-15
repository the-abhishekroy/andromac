package app.andromac

import android.content.Context
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File

/** Andromac's built-in Tailscale node (no separate Tailscale app needed). */
object Net {
    /** starting | login | running | error */
    var state by mutableStateOf("starting"); private set
    var loginUrl by mutableStateOf<String?>(null); private set
    var ip by mutableStateOf<String?>(null); private set
    var detail by mutableStateOf(""); private set
    var account by mutableStateOf(""); private set      // signed-in login name
    var deviceName by mutableStateOf(""); private set
    private var started = false
    private val proxies = HashMap<String, Int>()
    private var bridgeUp = false

    /** Terminal bridge: Termux can `ssh -p 2222 <user>@127.0.0.1` to reach the Mac even when the Tailscale app is off.
     *  Sessions live inside this process, so they survive Wi-Fi / mobile-data switches. */
    @Synchronized fun ensureBridge(macHost: String) {
        if (bridgeUp || state != "running" || !Settings.terminalBridge) return
        try { app.andromac.tunnel.Tunnel.proxyOn(2222, "$macHost:22"); bridgeUp = true } catch (e: Throwable) { /* port busy or tunnel not ready: retried on next connect */ }
        // the other direction: the Mac reaches this phone's Termux SSH server (port 8022) through the tunnel
        try { app.andromac.tunnel.Tunnel.serve(8022, "127.0.0.1:8022") } catch (e: Throwable) { }
    }

    fun start(ctx: Context) {
        if (started) return
        started = true
        val dir = File(ctx.filesDir, "tailscale").apply { mkdirs() }.absolutePath
        val host = "andromac-" + Build.MODEL.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
        Thread({
            try {
                app.andromac.tunnel.Tunnel.start(dir, host, object : app.andromac.tunnel.Listener {
                    override fun onState(s: String, d: String) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            when (s) {
                                "login" -> { state = "login"; loginUrl = d; ip = null; account = "" }
                                "running" -> { state = "running"; loginUrl = null; ip = d; proxies.clear(); Link.restart() }
                                "account" -> { val p = d.split("|"); account = p.getOrElse(0) { "" }; deviceName = p.getOrElse(1) { "" } }
                                "error" -> { state = "error"; detail = d }
                                else -> if (state != "login" && state != "running") state = "starting"
                            }
                        }
                    }
                })
            } catch (e: Throwable) {
                android.os.Handler(android.os.Looper.getMainLooper()).post { state = "error"; detail = e.message ?: e.toString() }
            }
        }, "andromac-tailscale").start()
    }

    /** Sign out of the built-in network; a new sign-in link appears (use it to switch accounts). */
    fun signOut() {
        Thread({
            try { app.andromac.tunnel.Tunnel.logout() }
            catch (e: Throwable) { android.os.Handler(android.os.Looper.getMainLooper()).post { state = "error"; detail = e.message ?: "sign-out failed" } }
        }, "andromac-signout").start()
        proxies.clear()
    }

    /** Local port that tunnels to host:port over the tailnet, or null if the node isn't up yet. */
    @Synchronized fun proxy(host: String, port: Int): Int? {
        if (state != "running") return null
        val key = "$host:$port"
        proxies[key]?.let { return it }
        return try { app.andromac.tunnel.Tunnel.proxy(key).toInt().also { proxies[key] = it } } catch (e: Throwable) { null }
    }
}
