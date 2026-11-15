package app.andromac

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin

/** The Andromac orbit mark: a tilted ring (silver to green) with a silver and a green dot and a soft glow. */
@Composable
fun OrbitLogo(size: Dp, pulse: Boolean, modifier: Modifier = Modifier) {
    val reduced = rememberReducedMotion()
    val anim = rememberInfiniteTransition(label = "orbit")
    val p by anim.animateFloat(0f, 1f, infiniteRepeatable(tween(2400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "p")
    val live = pulse && !reduced
    val t = if (live) p else 0f
    Canvas(modifier.size(size).scale(1f + 0.05f * t)) {
        val s = this.size.minDimension
        val c = Offset(s / 2, s / 2)
        drawCircle(
            Brush.radialGradient(listOf(Brand.Green.copy(alpha = 0.08f + 0.08f * t), Color.Transparent), c, s * 0.5f),
            radius = s * 0.5f, center = c,
        )
        drawCircle(
            Brush.radialGradient(listOf(Color(0xFF2A2A2A), Brand.Navy2), c, s * 0.2f),
            radius = s * 0.17f, center = c,
        )
        val rx = s * 0.40f; val ry = s * 0.16f; val tilt = -28f
        withTransform({ rotate(tilt, c) }) {
            drawOval(
                Brush.linearGradient(listOf(Brand.Silver, Color(0xFFB5E8B5), Brand.Green), Offset(c.x - rx, c.y), Offset(c.x + rx, c.y)),
                topLeft = Offset(c.x - rx, c.y - ry), size = Size(rx * 2, ry * 2),
                style = Stroke(width = s * 0.05f, cap = StrokeCap.Round),
            )
        }
        fun pt(deg: Float): Offset {
            val a = Math.toRadians(deg.toDouble()); val r = Math.toRadians(tilt.toDouble())
            val x = rx * cos(a); val y = ry * sin(a)
            return Offset(c.x + (x * cos(r) - y * sin(r)).toFloat(), c.y + (x * sin(r) + y * cos(r)).toFloat())
        }
        drawCircle(Brand.Silver, s * 0.055f, pt(205f))
        drawCircle(Brand.Green.copy(alpha = 0.35f), s * 0.10f, pt(25f))
        drawCircle(Brand.Green, s * 0.062f, pt(25f))
    }
}
