package app.andromac

import android.app.*
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/** Transparent activity that asks Android for screen-capture consent, then starts the service. */
class ScreenConsentActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val mpm = getSystemService(MediaProjectionManager::class.java)
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), 77)
    }
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        if (req == 77 && res == RESULT_OK && data != null) {
            startForegroundService(Intent(this, ScreenShareService::class.java)
                .putExtra("code", res).putExtra("data", data))
        } else {
            Link.send("screen_stopped", JSONObject().put("reason", "denied"))
        }
        finish()
    }
}

/** Captures the screen, encodes H.264 and streams it to the Mac over the Andromac link. */
class ScreenShareService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var codec: MediaCodec? = null
    @Volatile private var running = false
    private var config: ByteArray? = null

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("screen", "Screen sharing", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 1, Intent(this, ScreenShareService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, "screen").setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Sharing your screen with your Mac").setOngoing(true)
            .addAction(0, "Stop", stop).build()
        startForeground(2, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        val data = intent?.getParcelableExtra<Intent>("data") ?: run { stopSelf(); return START_NOT_STICKY }
        startCapture(intent.getIntExtra("code", Activity.RESULT_OK), data)
        return START_NOT_STICKY
    }

    private var curW = 0; private var curH = 0
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) {}
        override fun onDisplayRemoved(id: Int) {}
        override fun onDisplayChanged(id: Int) { if (id == android.view.Display.DEFAULT_DISPLAY) onRotated() }
    }

    private fun targetSize(): Pair<Int, Int> {
        val b = getSystemService(android.view.WindowManager::class.java).maximumWindowMetrics.bounds
        val scale = minOf(1f, 1280f / maxOf(b.width(), b.height()))
        return ((b.width() * scale).toInt() / 2 * 2) to ((b.height() * scale).toInt() / 2 * 2)
    }

    private fun newEncoder(w: Int, h: Int): MediaCodec {
        val fmt = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, MAX_BITRATE / 2)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            setInteger(MediaFormat.KEY_FRAME_RATE, 60)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 3)
            setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 250_000)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            setInteger(MediaFormat.KEY_LATENCY, 1)
        }
        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        c.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        return c
    }

    private fun startCapture(code: Int, data: Intent) {
        val mpm = getSystemService(MediaProjectionManager::class.java)
        val p = mpm.getMediaProjection(code, data)
        projection = p
        p.registerCallback(object : MediaProjection.Callback() { override fun onStop() { stopSelf() } }, null)

        val (w, h) = targetSize(); curW = w; curH = h
        val c = newEncoder(w, h)
        val surface = c.createInputSurface()
        c.start()
        codec = c
        display = p.createVirtualDisplay("andromac", w, h, resources.displayMetrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null)
        A11yToggle.enable(this)       // control service is on only for the duration of this session
        running = true
        Link.send("screen_started", JSONObject().put("w", w).put("h", h))
        Thread({ drain(c) }, "andromac-encoder").start()
        ScreenShareState.active = true
        wireKeyframe(c)
        getSystemService(DisplayManager::class.java).registerDisplayListener(displayListener, android.os.Handler(mainLooper))
    }

    private fun wireKeyframe(c: MediaCodec) {
        ScreenShareState.requestKeyframe = { runCatching { c.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) } }
    }

    /** The phone rotated: rebuild the encoder at the new size and re-point the virtual display, then tell the Mac. */
    @Synchronized private fun onRotated() {
        if (!running) return
        val (w, h) = targetSize()
        if (w == curW && h == curH) return
        curW = w; curH = h
        val old = codec
        val c = newEncoder(w, h)
        val surface = c.createInputSurface()
        c.start()
        config = null
        codec = c
        display?.resize(w, h, resources.displayMetrics.densityDpi)
        display?.surface = surface
        Thread({ drain(c) }, "andromac-encoder").start()
        wireKeyframe(c)
        runCatching { old?.stop(); old?.release() }
        Link.send("screen_started", JSONObject().put("w", w).put("h", h))
    }

    private var bitrate = MAX_BITRATE / 2
    private var needKey = false
    private var lastAdapt = 0L
    private var calmSince = 0L

    private fun setBitrate(c: MediaCodec, bps: Int) {
        bitrate = bps.coerceIn(MIN_BITRATE, MAX_BITRATE)
        runCatching { c.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate) }) }
    }

    /** Congestion control: when the link backs up, fall back to a keyframe and a lower bitrate; recover slowly when calm. */
    private fun adapt(c: MediaCodec, queued: Long) {
        val now = System.currentTimeMillis()
        if (queued > 120_000) { calmSince = 0; if (now - lastAdapt > 700) { lastAdapt = now; setBitrate(c, bitrate * 3 / 4) } }
        else if (queued < 20_000) {
            if (calmSince == 0L) calmSince = now
            if (now - calmSince > 3000 && now - lastAdapt > 1500) { lastAdapt = now; calmSince = now; setBitrate(c, bitrate * 11 / 10) }
        }
    }

    private fun drain(c: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        needKey = false
        while (running && codec === c) {
            val i = try { c.dequeueOutputBuffer(info, 100_000) } catch (e: Exception) { break }
            if (i < 0) continue
            val buf = c.getOutputBuffer(i)
            if (buf != null && info.size > 0) {
                val bytes = ByteArray(info.size).also { buf.position(info.offset); buf.get(it) }
                when {
                    info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0 -> config = bytes
                    else -> {
                        val key = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                        val q = Link.queuedBytes()
                        adapt(c, q)
                        when {
                            key -> { needKey = false; Link.sendVideo(1, if (config != null) config!! + bytes else bytes) }
                            needKey -> {}                       // reference chain is broken: wait for the next keyframe
                            q > 160_000 -> {                    // never drop deltas silently: that smears the picture
                                needKey = true
                                runCatching { c.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
                            }
                            else -> Link.sendVideo(0, bytes)
                        }
                    }
                }
            }
            c.releaseOutputBuffer(i, false)
        }
    }

    override fun onDestroy() {
        A11yToggle.disable(this)
        running = false
        runCatching { getSystemService(DisplayManager::class.java).unregisterDisplayListener(displayListener) }
        ScreenShareState.active = false
        ScreenShareState.requestKeyframe = null
        runCatching { codec?.stop(); codec?.release() }
        runCatching { display?.release() }
        runCatching { projection?.stop() }
        Link.send("screen_stopped", JSONObject().put("reason", "stopped"))
        super.onDestroy()
    }
}

private const val MAX_BITRATE = 8_000_000
private const val MIN_BITRATE = 1_200_000

object ScreenShareState {
    @Volatile var active = false
    @Volatile var requestKeyframe: (() -> Unit)? = null
    fun start(ctx: Context) { ctx.startActivity(Intent(ctx, ScreenConsentActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    fun stop(ctx: Context) { ctx.startService(Intent(ctx, ScreenShareService::class.java).setAction("stop")) }
}
