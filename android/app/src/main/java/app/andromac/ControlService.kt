package app.andromac

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject
import kotlin.math.hypot

/** Executes taps, swipes, nav keys and typing sent by the Mac. Only acts while a share session is active. */
class ControlService : AccessibilityService() {
    companion object {
        @Volatile var instance: ControlService? = null
        fun handle(d: JSONObject) { instance?.run(d) }
    }

    // ----- live touch engine: one continuous finger stroke, streamed in short segments -----
    private var strokeSd: GestureDescription.StrokeDescription? = null
    private var lastX = 0f; private var lastY = 0f
    private var targetX = 0f; private var targetY = 0f
    private var downAt = 0L; private var lastSegAt = 0L
    private var moved = false; private var ending = false; private var busy = false; private var active = false

    override fun onServiceConnected() { instance = this }
    override fun onUnbind(intent: android.content.Intent?): Boolean { instance = null; return super.onUnbind(intent) }
    override fun onAccessibilityEvent(e: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    private fun size(): Pair<Int, Int> {
        val b = getSystemService(android.view.WindowManager::class.java).currentWindowMetrics.bounds
        return b.width() to b.height()
    }

    /** Fallback when Android blocks starting the app from the background: pull the shade down and tap the notification. */
    fun openNotification(title: String): Boolean {
        if (title.isEmpty()) return false
        performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
        android.os.Handler(mainLooper).postDelayed({
            val node = rootInActiveWindow?.findAccessibilityNodeInfosByText(title)?.firstOrNull()
            var n: AccessibilityNodeInfo? = node
            while (n != null && !n.isClickable) n = n.parent
            n?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }, 900)
        return true
    }

    fun run(d: JSONObject) {
        if (!ScreenShareState.active) return           // never act unless the user started sharing
        val (w, h) = size()
        when (d.optString("k")) {
            "down" -> { cancelStroke(); active = true; moved = false; ending = false
                lastX = d.optDouble("x").toFloat() * w; lastY = d.optDouble("y").toFloat() * h
                targetX = lastX; targetY = lastY; downAt = System.currentTimeMillis(); lastSegAt = downAt }
            "move" -> if (active) { targetX = d.optDouble("x").toFloat() * w; targetY = d.optDouble("y").toFloat() * h
                if (!moved && hypot(targetX - lastX, targetY - lastY) < 6f) return   // ignore jitter so taps stay taps
                moved = true; pump() }
            "up" -> if (active) { targetX = d.optDouble("x").toFloat() * w; targetY = d.optDouble("y").toFloat() * h
                ending = true; pump() }
            "scroll" -> {   // mouse-wheel style: one short swipe
                val x = d.optDouble("x").toFloat() * w; val y = d.optDouble("y").toFloat() * h
                val dy = d.optDouble("dy").toFloat() * h * 0.6f
                swipe(x, y, x, (y - dy).coerceIn(10f, h - 10f), 220)
            }
            "pinch" -> pinch(d.optDouble("x").toFloat() * w, d.optDouble("y").toFloat() * h, d.optDouble("s", 1.0).toFloat(), w, h)
            "rotate" -> rotate(d.optDouble("x").toFloat() * w, d.optDouble("y").toFloat() * h, d.optDouble("deg", 0.0).toFloat(), w, h)
            "paste" -> findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            "selectall" -> findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.let { n ->
                val len = n.text?.length ?: 0
                n.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0); putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, len) })
            }
            "nav" -> when (d.optString("a")) {
                "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
                "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
                "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
                "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
                "quicksettings" -> performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
                "lock" -> performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
                "screenshot" -> performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT)
                "volup" -> getSystemService(android.media.AudioManager::class.java).adjustStreamVolume(android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.ADJUST_RAISE, android.media.AudioManager.FLAG_SHOW_UI)
                "voldown" -> getSystemService(android.media.AudioManager::class.java).adjustStreamVolume(android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.ADJUST_LOWER, android.media.AudioManager.FLAG_SHOW_UI)
            }
            "text" -> typeText(d.optString("t"))
            "key" -> when (d.optString("c")) {
                "backspace" -> editFocused { it.dropLast(1) }
                "enter" -> findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
            }
        }
    }

    private fun cancelStroke() { strokeSd = null; busy = false; active = false; moved = false; ending = false }

    /** Dispatch the next segment of the current finger stroke (coalescing moves while one is in flight). */
    private fun pump() {
        if (busy) return
        val now = System.currentTimeMillis()
        val finishing = ending
        if (!finishing && targetX == lastX && targetY == lastY) return
        val p = Path().apply {
            moveTo(lastX, lastY)
            if (targetX == lastX && targetY == lastY) lineTo(lastX + 0.1f, lastY) else lineTo(targetX, targetY)
        }
        val first = strokeSd == null
        val dur = if (first) (now - downAt).coerceIn(if (finishing) 40 else 20, 1500)   // holding first = long-press / selection
                  else (now - lastSegAt).coerceIn(16, 120)
        val willContinue = !finishing
        val sd = try {
            if (first) GestureDescription.StrokeDescription(p, 0, dur, willContinue)
            else strokeSd!!.continueStroke(p, 0, dur, willContinue)
        } catch (e: Exception) { cancelStroke(); return }
        strokeSd = sd; busy = true; lastSegAt = now
        val ok = dispatchGesture(GestureDescription.Builder().addStroke(sd).build(), object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) {
                busy = false; lastX = targetX; lastY = targetY
                if (finishing) { strokeSd = null; active = false } else pump()
            }
            override fun onCancelled(g: GestureDescription?) { busy = false; if (finishing) { strokeSd = null; active = false } else strokeSd = null }
        }, null)
        if (!ok) { busy = false; strokeSd = null }
    }

    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, ms: Long) {
        val p = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(p, 0, ms)).build(), null, null)
    }

    /** Two fingers rotating around (cx, cy) by `deg` degrees (positive = clockwise). */
    private fun rotate(cx: Float, cy: Float, deg: Float, w: Int, h: Int) {
        val r = (minOf(w, h) * 0.14f).coerceAtMost(minOf(cx, w - cx, cy, h - cy).coerceAtLeast(40f))
        fun arc(startDeg: Float): GestureDescription.StrokeDescription {
            val p = Path()
            val steps = 8
            for (i in 0..steps) {
                val a = Math.toRadians((startDeg + deg * i / steps).toDouble())
                val x = cx + r * Math.cos(a).toFloat(); val y = cy + r * Math.sin(a).toFloat()
                if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
            }
            return GestureDescription.StrokeDescription(p, 0, 350)
        }
        dispatchGesture(GestureDescription.Builder().addStroke(arc(0f)).addStroke(arc(180f)).build(), null, null)
    }

    /** Two fingers moving apart (s>1) or together (s<1) around (cx, cy). */
    private fun pinch(cx: Float, cy: Float, s: Float, w: Int, h: Int) {
        val scale = s.coerceIn(0.25f, 4f)
        val d = minOf(w, h) * 0.12f
        val d2 = (d * scale).coerceIn(d * 0.3f, minOf(cx, w - cx, cy, h - cy).coerceAtLeast(d))
        fun stroke(from: Float, to: Float): GestureDescription.StrokeDescription {
            val p = Path().apply { moveTo(cx + from, cy); lineTo(cx + to, cy) }
            return GestureDescription.StrokeDescription(p, 0, 300)
        }
        dispatchGesture(GestureDescription.Builder().addStroke(stroke(-d, -d2)).addStroke(stroke(d, d2)).build(), null, null)
    }

    private fun typeText(t: String) = editFocused { it + t }

    private fun editFocused(f: (String) -> String) {
        val n = findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return
        val cur = n.text?.toString()?.takeIf { !n.isShowingHintText } ?: ""
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, f(cur)) }
        n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }
}
