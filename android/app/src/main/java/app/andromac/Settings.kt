package app.andromac

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** User settings. Backed by SharedPreferences, observable from Compose. */
object Settings {
    private lateinit var sp: android.content.SharedPreferences
    private var loaded = false

    var mirrorNotifications by mutableStateOf(true); private set
    var showMacNotifications by mutableStateOf(true); private set
    var forwardSms by mutableStateOf(true); private set
    var hideOngoing by mutableStateOf(true); private set
    var muted by mutableStateOf<Set<String>>(emptySet()); private set
    var keepConnected by mutableStateOf(true); private set
    var syncClipboard by mutableStateOf(true); private set
    var terminalBridge by mutableStateOf(true); private set
    var fileShare by mutableStateOf(false); private set          // share phone storage with the Mac (off by default)
    var fileWrite by mutableStateOf(false); private set          // allow the Mac to change files (read-only by default)

    fun load(ctx: Context) {
        if (loaded) return
        sp = ctx.applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
        mirrorNotifications = sp.getBoolean("mirror", true)
        showMacNotifications = sp.getBoolean("mac", true)
        forwardSms = sp.getBoolean("sms", true)
        hideOngoing = sp.getBoolean("ongoing", true)
        muted = sp.getStringSet("muted", emptySet()) ?: emptySet()
        keepConnected = sp.getBoolean("keep", true)
        syncClipboard = sp.getBoolean("clip", true)
        terminalBridge = sp.getBoolean("term", true)
        fileShare = sp.getBoolean("fshare", false)
        fileWrite = sp.getBoolean("fwrite", false)
        loaded = true
    }

    fun updateKeepConnected(v: Boolean) { keepConnected = v; sp.edit().putBoolean("keep", v).apply() }
    fun updateFileShare(v: Boolean) { fileShare = v; sp.edit().putBoolean("fshare", v).apply() }
    fun updateFileWrite(v: Boolean) { fileWrite = v; sp.edit().putBoolean("fwrite", v).apply() }
    fun updateTerminalBridge(v: Boolean) { terminalBridge = v; sp.edit().putBoolean("term", v).apply() }
    fun updateSyncClipboard(v: Boolean) { syncClipboard = v; sp.edit().putBoolean("clip", v).apply() }
    fun setMirror(v: Boolean) { mirrorNotifications = v; sp.edit().putBoolean("mirror", v).apply() }
    fun setMac(v: Boolean) { showMacNotifications = v; sp.edit().putBoolean("mac", v).apply() }
    fun setSms(v: Boolean) { forwardSms = v; sp.edit().putBoolean("sms", v).apply() }
    fun updateHideOngoing(v: Boolean) { hideOngoing = v; sp.edit().putBoolean("ongoing", v).apply() }
    fun setMuted(pkg: String, mute: Boolean) {
        muted = if (mute) muted + pkg else muted - pkg
        sp.edit().putStringSet("muted", muted.toSet()).apply()
    }
}
