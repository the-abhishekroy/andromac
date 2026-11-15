package app.andromac

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/** Clipboard images: shrink to a sane size and encode (PNG when transparent, otherwise JPEG) so they sync fast. */
object ImageCodec {
    private const val MAX_SIDE = 2048

    fun sha(b: ByteArray): String = MessageDigest.getInstance("SHA-1").digest(b).joinToString("") { "%02x".format(it) }.take(20)

    fun readUri(ctx: Context, uri: Uri): ByteArray? = runCatching {
        ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }.getOrNull()

    /** Returns the bytes to sync and their mime type, or null if this isn't a decodable image. */
    fun prepare(src: ByteArray): Pair<ByteArray, String>? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(src, 0, src.size, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_SIDE * 2) sample *= 2
        var bmp = BitmapFactory.decodeByteArray(src, 0, src.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val big = maxOf(bmp.width, bmp.height)
        if (big > MAX_SIDE) { val k = MAX_SIDE.toFloat() / big; bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * k).toInt(), (bmp.height * k).toInt(), true) }
        val out = ByteArrayOutputStream()
        val alpha = bmp.hasAlpha()
        if (alpha) bmp.compress(Bitmap.CompressFormat.PNG, 100, out) else bmp.compress(Bitmap.CompressFormat.JPEG, 88, out)
        val bytes = out.toByteArray()
        if (bytes.size > 6_000_000) return null           // too large to sync comfortably
        bytes to (if (alpha) "image/png" else "image/jpeg")
    }.getOrNull()

    fun thumbnail(bytes: ByteArray, maxSide: Int = 480): Bitmap? = runCatching {
        val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, b)
        var s = 1; while (maxOf(b.outWidth, b.outHeight) / s > maxSide * 2) s *= 2
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = s })
    }.getOrNull()
}
