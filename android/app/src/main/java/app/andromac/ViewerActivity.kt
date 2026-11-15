package app.andromac

import android.app.Activity
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.*
import android.view.inputmethod.InputMethodManager
import android.widget.*
import org.json.JSONObject

/** Shows the Mac's screen and sends touches back as mouse input. */
class ViewerActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var surface: SurfaceView
    private lateinit var status: TextView
    private lateinit var box: FrameLayout
    private var codec: MediaCodec? = null
    private var surfaceReady = false
    private var vw = 16; private var vh = 9
    private val ui = Handler(Looper.getMainLooper())
    private var gotFrame = false
    private lateinit var controls: LinearLayout
    private lateinit var restore: TextView
    private val mods = mutableSetOf<String>()
    private var trackpad = true
    private var curX = 0.5f; private var curY = 0.5f      // the Mac cursor, normalized (kept in sync from the Mac)
    @Volatile private var fingersDown = false

    private fun mac(action: String) { send(JSONObject().put("k", "mac").put("a", action)) }

    private fun applyImmersive(on: Boolean) {
        controls.visibility = if (on) View.GONE else View.VISIBLE
        restore.visibility = if (on) View.VISIBLE else View.GONE
        window.insetsController?.let {
            if (on) { it.hide(WindowInsets.Type.systemBars()); it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE }
            else it.show(WindowInsets.Type.systemBars())
        }
        surface.post { fit() }
    }

    private fun consumeMods(): List<String> = mods.toList().also { mods.clear() }

    private fun combo(m: List<String>, c: String) { send(JSONObject().put("k", "combo").put("m", org.json.JSONArray(m)).put("c", c)) }
    private fun sendKey(c: String) { val m = consumeMods(); if (m.isEmpty()) send(JSONObject().put("k", "key").put("c", c)) else combo(m, c) }
    private fun sendText(t: String) {
        if (mods.isNotEmpty() && t.length == 1) { combo(consumeMods(), t.lowercase()); return }
        send(JSONObject().put("k", "text").put("t", t))
    }

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Link.init(this)
        val dp = resources.displayMetrics.density
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF000000.toInt()) }
        box = FrameLayout(this)
        surface = SurfaceView(this).also { it.holder.addCallback(this) }
        box.addView(surface, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        status = TextView(this).apply { text = "Waiting for approval on your Mac…"; setTextColor(0xFFFFFFFF.toInt()); textSize = 16f; gravity = Gravity.CENTER }
        box.addView(status, FrameLayout.LayoutParams(-1, -1))
        root.addView(box, LinearLayout.LayoutParams(-1, 0, 1f))

        controls = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF000000.toInt()) }
        val input = EditText(this).apply {
            hint = "Type to Mac"; setSingleLine(); setTextColor(0xFFFFFFFF.toInt()); setHintTextColor(0xFF7E7E7E.toInt()); background = null
            setPadding((16 * dp).toInt(), (10 * dp).toInt(), (16 * dp).toInt(), (10 * dp).toInt())
            addTextChangedListener(object : TextWatcher {
                var busy = false
                override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) {}
                override fun onTextChanged(s: CharSequence?, st: Int, before: Int, count: Int) {
                    if (busy || s == null) return
                    repeat(before) { sendKey("backspace") }
                    if (count > 0) sendText(s.substring(st, st + count))
                }
                override fun afterTextChanged(e: Editable?) { busy = true; if ((e?.length ?: 0) > 40) e?.clear(); busy = false }
            })
        }
        controls.addView(input, LinearLayout.LayoutParams(-1, -2))
        // Same look as the Termux extra-keys row: flat, bold, letter-spaced labels on pure black, no boxes, every row on
        // one 7-column grid so the keys line up. Only Command and Option use their Mac symbols.
        val rowH = (46 * dp).toInt()
        fun key(label: String, weight: Float = 1f, desc: String = label, size: Float = 12.5f, action: (TextView) -> Unit): TextView = TextView(this).apply {
            text = label; typeface = android.graphics.Typeface.DEFAULT_BOLD; textSize = size; letterSpacing = 0.06f
            setTextColor(0xFFFFFFFF.toInt()); gravity = Gravity.CENTER; isClickable = true; isFocusable = true; contentDescription = desc
            foreground = android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33FFFFFF), null,
                android.graphics.drawable.ShapeDrawable(android.graphics.drawable.shapes.RectShape()))
            layoutParams = LinearLayout.LayoutParams(0, rowH, weight)
            setOnClickListener { action(this) }
        }
        fun row(vararg items: View) = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; weightSum = 7f; items.forEach { addView(it) }
            layoutParams = LinearLayout.LayoutParams(-1, -2)
        }
        fun mod(label: String, name: String, desc: String, size: Float = 12.5f) = key(label, 1f, desc, size) { t ->
            if (!mods.remove(name)) mods.add(name)
            t.setTextColor(if (name in mods) 0xFF87D787.toInt() else 0xFFFFFFFF.toInt())
        }
        controls.addView(row(key("ESC") { sendKey("esc") }, key("TAB") { sendKey("tab") },
            mod("⌘", "cmd", "Command", 20f), mod("⌥", "alt", "Option", 20f), mod("CTRL", "ctrl", "Control"), mod("SHIFT", "shift", "Shift"),
            key("DEL", 1f, "Delete") { sendKey("backspace") }))
        controls.addView(row(key("SPACE", 2f) { sendText(" ") }, key("ENTER", 1f, "Return") { sendKey("enter") },
            key("←", 1f, "Left") { sendKey("left") }, key("↓", 1f, "Down") { sendKey("down") }, key("↑", 1f, "Up") { sendKey("up") }, key("→", 1f, "Right") { sendKey("right") }))
        controls.addView(row(key("⌘TAB", 1f, "Switch app") { combo(listOf("cmd"), "tab") }, key("SPOTLIGHT", 2f) { combo(listOf("cmd"), "space") },
            key("MISSION", 2f, "Mission Control") { mac("mission") }, key("DESKTOP", 2f, "Show desktop") { mac("desktop") }))
        controls.addView(row(key("COPY") { combo(listOf("cmd"), "c") }, key("PASTE") { combo(listOf("cmd"), "v") }, key("CLOSE") { combo(listOf("cmd"), "w") },
            key("LOCK") { combo(listOf("cmd", "ctrl"), "q") },
            key(if (trackpad) "PAD" else "TOUCH", 1f, "Switch between trackpad and touch mode") { t ->
                trackpad = !trackpad; t.text = if (trackpad) "PAD" else "TOUCH"
                Toast.makeText(this, if (trackpad) "Trackpad mode: move, tap, 2-finger scroll, 3-finger drag, 4-finger swipe" else "Touch mode: tap where you want to click", Toast.LENGTH_SHORT).show()
            },
            key("ROTATE") { requestedOrientation = if (resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE)
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE },
            key("FULL", 1f, "Full screen") { applyImmersive(true) }))
        controls.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(-1, (6 * dp).toInt()) })
        root.addView(controls)
        restore = TextView(this).apply {
            text = "  ⛶  "; textSize = 22f; setTextColor(0xFFFFFFFF.toInt()); setBackgroundColor(0x88000000.toInt()); visibility = View.GONE
            setOnClickListener { applyImmersive(false) }
        }
        box.addView(restore, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.END))
        val endBtn = TextView(this).apply {
            text = "  ✕  "; textSize = 20f; setTextColor(0xFFFFFFFF.toInt()); setBackgroundColor(0x88000000.toInt()); contentDescription = "End session"
            setOnClickListener { finish() }
        }
        box.addView(endBtn, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.START))
        // Android 15 draws edge to edge: keep the controls clear of the status and gesture bars
        root.setOnApplyWindowInsetsListener { v, ins ->
            val b = ins.getInsets(WindowInsets.Type.systemBars())
            v.setPadding(b.left, b.top, b.right, b.bottom); ins
        }
        setContentView(root)

        Link.macScreen = { type, d -> ui.post { onMacMessage(type, d) } }
        Link.videoSink = { flags, au -> feed(flags, au) }
        Link.send("mac_screen_request", JSONObject())
        setupTouch()
    }

    private fun onMacMessage(type: String, d: JSONObject) {
        when (type) {
            "mac_screen_started" -> { vw = d.optInt("w", 16); vh = d.optInt("h", 9); fit(); status.text = "Starting…"
                intent.getStringExtra("bundle")?.takeIf { it.isNotEmpty() }?.let { Link.send("mac_open_app", JSONObject().put("bundle", it)) } }
            "mac_screen_denied" -> { status.text = if (d.optString("reason") == "permission")
                "Your Mac can't share its screen yet. On the Mac, open Andromac and allow Screen Recording (a setup window opened there), then try again."
                else "The Mac declined this request." }
            "mac_screen_stopped" -> { status.text = "Mac stopped sharing."; status.visibility = View.VISIBLE }
            "cursor" -> if (!fingersDown) { curX = d.optDouble("x", curX.toDouble()).toFloat(); curY = d.optDouble("y", curY.toDouble()).toFloat() }
        }
    }

    private fun fit() {
        val bw = box.width.takeIf { it > 0 } ?: return; val bh = box.height
        val scale = minOf(bw.toFloat() / vw, bh.toFloat() / vh)
        surface.layoutParams = FrameLayout.LayoutParams((vw * scale).toInt(), (vh * scale).toInt(), Gravity.CENTER)
    }

    override fun surfaceCreated(h: SurfaceHolder) { surfaceReady = true }
    override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) {}
    override fun surfaceDestroyed(h: SurfaceHolder) { surfaceReady = false; stopCodec() }

    @Synchronized private fun feed(flags: Int, au: ByteArray) {
        if (!surfaceReady) return
        if (codec == null) {
            if (flags and 1 == 0) { Link.send("mac_keyframe", JSONObject()); return }   // wait for a keyframe
            val f = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080)
            f.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also {
                it.configure(f, surface.holder.surface, null, 0); it.start()
            }
            Thread({ drain(codec!!) }, "andromac-decoder").start()
        }
        val c = codec ?: return
        val i = try { c.dequeueInputBuffer(5_000) } catch (e: Exception) { -1 }
        if (i >= 0) {
            c.getInputBuffer(i)?.apply { clear(); put(au) }
            c.queueInputBuffer(i, 0, au.size, System.nanoTime() / 1000, 0)
        }
    }

    private fun drain(c: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (codec === c) {
            val o = try { c.dequeueOutputBuffer(info, 50_000) } catch (e: Exception) { break }
            if (o >= 0) {
                c.releaseOutputBuffer(o, true)
                if (!gotFrame) { gotFrame = true; ui.post { status.visibility = View.GONE } }
            }
        }
    }

    @Synchronized private fun stopCodec() { runCatching { codec?.stop(); codec?.release() }; codec = null }

    private fun send(d: JSONObject) { Link.send("input", d.put("target", "mac")) }

    // ----- touch handling -----
    // TRACKPAD mode (default, like the MacBook):  1 finger = move cursor, tap = click, double tap = double click
    //   2 fingers = scroll, pinch = zoom, quick tap = right-click     3 fingers = drag (click-and-drag / select)
    //   4 fingers = swipe left/right switches Space, up = Mission Control, down = App Exposé
    // TOUCH mode: tap exactly where you want; long-press = right-click; 2 fingers scroll; 3 or 4 fingers swipe like above.
    private fun setupTouch() {
        val dp = resources.displayMetrics.density
        var lastCx = 0f; var lastCy = 0f; var recenter = true
        var downAt = 0L; var travel = 0f; var mode = 0
        var startDist = 0f; var lastZoom = 0f; var twoMoved = false; var twoStart = 0L
        var swipeX = 0f; var swipeY = 0f; var swipeDone = false; var dragging = false
        var lastSend = 0L
        // touch-mode only
        var sx = 0f; var sy = 0f; var longFired = false
        val longPress = Runnable { longFired = true; send(JSONObject().put("k", "rclick").put("x", sx).put("y", sy)) }
        fun dist(e: MotionEvent) = Math.hypot((e.getX(0) - e.getX(1)).toDouble(), (e.getY(0) - e.getY(1)).toDouble()).toFloat()
        fun cx(e: MotionEvent): Float { var t = 0f; for (i in 0 until e.pointerCount) t += e.getX(i); return t / e.pointerCount }
        fun cy(e: MotionEvent): Float { var t = 0f; for (i in 0 until e.pointerCount) t += e.getY(i); return t / e.pointerCount }
        fun pos(k: String) = JSONObject().put("k", k).put("x", curX).put("y", curY)

        surface.setOnTouchListener { v, e ->
            val w = v.width.toFloat().coerceAtLeast(1f); val h = v.height.toFloat().coerceAtLeast(1f)
            val n = e.pointerCount
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    fingersDown = true; mode = 1; downAt = System.currentTimeMillis(); travel = 0f; recenter = true; swipeDone = false; dragging = false
                    if (!trackpad) {
                        sx = (e.x / w).coerceIn(0f, 1f); sy = (e.y / h).coerceIn(0f, 1f); longFired = false
                        send(JSONObject().put("k", "down").put("x", sx).put("y", sy)); ui.postDelayed(longPress, 600)
                    }
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    ui.removeCallbacks(longPress)
                    if (!trackpad && mode == 1 && !longFired) send(JSONObject().put("k", "up").put("x", (e.x / w).coerceIn(0f, 1f)).put("y", (e.y / h).coerceIn(0f, 1f)))
                    recenter = true
                    when {
                        n == 2 -> { mode = 2; twoMoved = false; twoStart = System.currentTimeMillis(); startDist = dist(e); lastZoom = startDist }
                        n == 3 && trackpad -> { mode = 3; dragging = true; send(pos("down")) }
                        n >= 3 -> { mode = 4; swipeX = cx(e); swipeY = cy(e); swipeDone = false }
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    val ex = cx(e); val ey = cy(e)
                    if (recenter) { lastCx = ex; lastCy = ey; recenter = false }
                    val dx = ex - lastCx; val dy = ey - lastCy; lastCx = ex; lastCy = ey
                    travel += Math.hypot(dx.toDouble(), dy.toDouble()).toFloat()
                    when (mode) {
                        1 -> if (trackpad) {
                            if (travel > 6 * dp) {
                                val speed = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat() / dp
                                val gain = if (speed > 14f) 2.6f else if (speed > 6f) 2.0f else 1.5f      // pointer acceleration
                                curX = (curX + dx / w * gain).coerceIn(0f, 1f); curY = (curY + dy / h * gain).coerceIn(0f, 1f)
                                val now = System.currentTimeMillis()
                                if (now - lastSend > 8) { lastSend = now; send(pos("hover")) }
                            }
                        } else if (!longFired) {
                            val nx = (e.x / w).coerceIn(0f, 1f); val ny = (e.y / h).coerceIn(0f, 1f)
                            if (Math.abs(nx - sx) + Math.abs(ny - sy) > 0.01f) ui.removeCallbacks(longPress)
                            val now = System.currentTimeMillis()
                            if (now - lastSend > 8) { lastSend = now; send(JSONObject().put("k", "move").put("x", nx).put("y", ny)) }
                        }
                        2 -> {
                            val d = dist(e); val ratio = d / startDist.coerceAtLeast(1f)
                            if (Math.abs(ratio - 1f) > 0.12f && Math.abs(d - lastZoom) > w * 0.06f) {
                                twoMoved = true; combo(listOf("cmd"), if (d > lastZoom) "=" else "-"); lastZoom = d
                            } else if (Math.abs(dy) > 1f) {
                                twoMoved = true
                                send(JSONObject().put("k", "scroll").put("x", curX).put("y", curY).put("dy", dy / h))
                            }
                        }
                        3 -> {   // three-finger drag
                            curX = (curX + dx / w * 1.8f).coerceIn(0f, 1f); curY = (curY + dy / h * 1.8f).coerceIn(0f, 1f)
                            val now = System.currentTimeMillis()
                            if (now - lastSend > 8) { lastSend = now; send(pos("move")) }
                        }
                        4 -> if (!swipeDone) {
                            val tx = ex - swipeX; val ty = ey - swipeY
                            if (Math.abs(tx) > w * 0.16f || Math.abs(ty) > h * 0.10f) {
                                swipeDone = true
                                if (Math.abs(tx) > Math.abs(ty)) combo(listOf("ctrl"), if (tx > 0) "left" else "right")   // swipe right = previous Space
                                else if (ty < 0) mac("mission") else combo(listOf("ctrl"), "down")                       // up = Mission Control, down = App Exposé
                            }
                        }
                    }
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    recenter = true
                    if (mode == 2 && !twoMoved && System.currentTimeMillis() - twoStart < 260) send(pos("rclick"))   // two-finger tap = right-click
                    if (mode == 3 && dragging) { dragging = false; send(pos("up")) }
                    mode = if (n - 1 >= 2) mode else 1
                    if (n - 1 < 2) mode = 0
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    ui.removeCallbacks(longPress)
                    if (trackpad) {
                        if (mode == 1 && System.currentTimeMillis() - downAt < 260 && travel < 10 * dp) { send(pos("down")); send(pos("up")) }   // tap = click
                        if (dragging) { dragging = false; send(pos("up")) }
                    } else if (mode == 1 && !longFired) send(JSONObject().put("k", "up").put("x", (e.x / w).coerceIn(0f, 1f)).put("y", (e.y / h).coerceIn(0f, 1f)))
                    mode = 0; fingersDown = false
                }
            }
            true
        }
    }

    override fun onDestroy() {
        Link.send("mac_screen_stop", JSONObject())
        Link.macScreen = null; Link.videoSink = null
        stopCodec(); super.onDestroy()
    }
}
