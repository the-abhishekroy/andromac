package app.andromac

import android.graphics.*
import android.util.Base64

/** App icon + a small device badge, so a notification shows the real app and where it came from. */
object Badge {
    fun decode(b64: String): Bitmap? = runCatching {
        val bytes = Base64.decode(b64, Base64.DEFAULT); BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }.getOrNull()

    fun encode(bmp: Bitmap): String {
        val out = java.io.ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    /** Draws a laptop badge in the bottom-right corner (for notifications that came from the Mac). */
    fun withMacBadge(base: Bitmap?): Bitmap {
        val size = 192
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        if (base != null) c.drawBitmap(Bitmap.createScaledBitmap(base, size, size, true), 0f, 0f, null)
        else c.drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF1C1C1E.toInt() })
        val r = size * 0.24f; val cx = size - r - 2; val cy = size - r - 2
        c.drawCircle(cx, cy, r + 4, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF000000.toInt() })
        c.drawCircle(cx, cy, r, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFF5F5F5.toInt() })
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF111111.toInt(); style = Paint.Style.STROKE; strokeWidth = size * 0.028f; strokeCap = Paint.Cap.ROUND }
        val w = r * 1.0f; val h = r * 0.62f
        c.drawRoundRect(RectF(cx - w / 2, cy - h / 2 - r * 0.1f, cx + w / 2, cy + h / 2 - r * 0.1f), 4f, 4f, p)   // screen
        c.drawLine(cx - w * 0.68f, cy + h / 2 + r * 0.12f, cx + w * 0.68f, cy + h / 2 + r * 0.12f, p)              // base
        return out
    }
}
