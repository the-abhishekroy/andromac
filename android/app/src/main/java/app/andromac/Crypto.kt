package app.andromac

import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Frame = nonce(12) || ciphertext || tag(16), ChaCha20-Poly1305. Matches the Mac side. */
class Channel(secret: ByteArray) {
    private val key: SecretKeySpec
    private val rng = SecureRandom()

    init {
        // HKDF-SHA256, 32 bytes (single expand block)
        val prk = hmac("andromac-v1".toByteArray(), secret)
        val okm = hmac(prk, "msg-key".toByteArray() + byteArrayOf(1))
        key = SecretKeySpec(okm, "ChaCha20")
    }

    private fun hmac(k: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(k, "HmacSHA256")) }.doFinal(data)

    fun seal(plain: ByteArray): ByteArray {
        val nonce = ByteArray(12).also { rng.nextBytes(it) }
        val c = Cipher.getInstance("ChaCha20-Poly1305")
        c.init(Cipher.ENCRYPT_MODE, key, IvParameterSpec(nonce))
        return nonce + c.doFinal(plain)
    }

    fun open(frame: ByteArray): ByteArray? = try {
        if (frame.size < 28) null else {
            val c = Cipher.getInstance("ChaCha20-Poly1305")
            c.init(Cipher.DECRYPT_MODE, key, IvParameterSpec(frame.copyOfRange(0, 12)))
            c.doFinal(frame, 12, frame.size - 12)
        }
    } catch (e: Exception) { null }

    companion object {
        fun decodeSecret(b64url: String): ByteArray =
            Base64.decode(b64url, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
