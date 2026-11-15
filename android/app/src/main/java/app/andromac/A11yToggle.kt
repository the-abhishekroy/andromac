package app.andromac

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings

/**
 * Payment and banking apps refuse to run while an accessibility service that can tap for another device is switched on.
 * So Andromac's control service is kept OFF and is switched on only while you are controlling the phone from the Mac,
 * then off again. Needs a one-time grant of WRITE_SECURE_SETTINGS (see docs/ANDROID-NOTES.md); without it you can still
 * switch the service on by hand in Android's settings.
 */
object A11yToggle {
    private fun component(ctx: Context) = ComponentName(ctx, ControlService::class.java).flattenToString()

    fun canToggle(ctx: Context) = ctx.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS") == PackageManager.PERMISSION_GRANTED

    fun isOn(ctx: Context): Boolean = split(ctx).contains(component(ctx))

    private fun split(ctx: Context): List<String> =
        (Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "").split(':').filter { it.isNotBlank() }

    private fun write(ctx: Context, list: List<String>) {
        Settings.Secure.putString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, list.joinToString(":"))
        Settings.Secure.putInt(ctx.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, if (list.isEmpty()) 0 else 1)
    }

    /** Switch our service on (keeping every other accessibility service exactly as it was). */
    fun enable(ctx: Context): Boolean {
        if (!canToggle(ctx)) return false
        return runCatching { val l = split(ctx); if (component(ctx) !in l) write(ctx, l + component(ctx)); true }.getOrDefault(false)
    }

    /** Switch our service off again, leaving other accessibility services untouched. */
    fun disable(ctx: Context) {
        if (!canToggle(ctx)) return
        runCatching { val l = split(ctx); if (component(ctx) in l) write(ctx, l - component(ctx)) }
        ControlService.instance?.disableSelf()
    }
}
