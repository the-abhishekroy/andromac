package app.andromac

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import kotlin.math.cos
import kotlin.math.sin

/** The Andromac orbit mark, flat: a tilted ring with a silver and a green dot. Static (no decorative loop). */
@Composable
fun OrbitLogo(size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension
        val c = Offset(s / 2, s / 2)
        drawCircle(Brand.Navy3, radius = s * 0.17f, center = c)
        val rx = s * 0.40f; val ry = s * 0.16f; val tilt = -28f
        withTransform({ rotate(tilt, c) }) {
            drawOval(
                Brand.Green, topLeft = Offset(c.x - rx, c.y - ry), size = Size(rx * 2, ry * 2),
                style = Stroke(width = s * 0.05f, cap = StrokeCap.Round),
            )
        }
        fun pt(deg: Float): Offset {
            val a = Math.toRadians(deg.toDouble()); val r = Math.toRadians(tilt.toDouble())
            val x = rx * cos(a); val y = ry * sin(a)
            return Offset(c.x + (x * cos(r) - y * sin(r)).toFloat(), c.y + (x * sin(r) + y * cos(r)).toFloat())
        }
        drawCircle(Brand.Silver, s * 0.055f, pt(205f))
        drawCircle(Brand.Green, s * 0.07f, pt(25f))
    }
}
