package app.andromac

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

// ---------- entrance motion ----------
/** True once the first screen has played its entrance; later tab visits do not animate again. */
internal var introPlayed = false

/** Slide-up + fade for list/section entrance. Stagger is capped at 6 items and only plays on first load. */
@Composable
internal fun Modifier.staggerIn(index: Int): Modifier {
    val reduced = LocalReduced.current
    val play = remember { !introPlayed && !reduced }
    if (!play) return this
    val a = remember { Animatable(0f) }
    LaunchedEffect(Unit) { delay(minOf(index, 6) * 40L); a.animateTo(1f, tween(Mo.Slow, easing = Mo.Emph)) }
    return this.graphicsLayer { alpha = a.value; translationY = (1f - a.value) * 24.dp.toPx() }
}

// ---------- layout ----------
@Composable
internal fun Page(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Sp.x4),
        verticalArrangement = Arrangement.spacedBy(Sp.x3),
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(top = Sp.x4, bottom = Sp.x1, start = Sp.x1).semantics { heading() })
        content()
        Spacer(Modifier.height(Sp.x6))
    }
}

/** Section header: small caps-style label, 24 above, 8 below (the 12 gap between cards is added by the page). */
@Composable
internal fun Heading(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium, letterSpacing = 0.6.sp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = Sp.x1, top = Sp.x3, bottom = 0.dp).semantics { heading() })
}

@Composable
internal fun AppCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) { Column(Modifier.fillMaxWidth(), content = content) }
}

@Composable
internal fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Sp.x2)) {
        Heading(title)
        AppCard { Column(Modifier.padding(vertical = Sp.x1), content = content) }
    }
}

@Composable
internal fun Body(text: String, modifier: Modifier = Modifier) =
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)

/** Card that reacts to touch: background steps up one surface level and the card scales to 0.97. */
@Composable
internal fun PressCard(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val c = MaterialTheme.colorScheme
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, moTween(Mo.Fast), label = "press")
    val bg by animateColorAsState(if (pressed) c.surfaceContainerHigh else c.surfaceContainer, moTween(Mo.Fast), label = "pressBg")
    Surface(
        onClick = onClick, enabled = enabled, interactionSource = src, shape = MaterialTheme.shapes.large, color = bg,
        border = BorderStroke(1.dp, c.outlineVariant),
        modifier = modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f).graphicsLayer { scaleX = scale; scaleY = scale },
    ) { Column(Modifier.fillMaxWidth(), content = content) }
}

// ---------- buttons ----------
@Composable
internal fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, moTween(Mo.Fast), label = "btn")
    Button(onClick, modifier.fillMaxWidth().heightIn(min = 52.dp).graphicsLayer { scaleX = scale; scaleY = scale },
        enabled = enabled, interactionSource = src, shape = RoundedCornerShape(50)) {
        if (icon != null) { Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(Sp.x2)) }
        Text(text, textAlign = TextAlign.Center)
    }
}

@Composable
internal fun TonalButton(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, moTween(Mo.Fast), label = "tbtn")
    FilledTonalButton(onClick, modifier.fillMaxWidth().heightIn(min = 48.dp).graphicsLayer { scaleX = scale; scaleY = scale },
        interactionSource = src, shape = RoundedCornerShape(50)) {
        if (icon != null) { Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(Sp.x2)) }
        Text(text, textAlign = TextAlign.Center)
    }
}

// ---------- switch ----------
/** 52x32 switch: thumb is 16 (off), 24 (on), 28 (pressed) and moves on a spring. Purely visual, the row owns the semantics. */
@Composable
internal fun AppSwitch(checked: Boolean, pressed: Boolean = false) {
    val c = MaterialTheme.colorScheme
    val track by animateColorAsState(if (checked) c.primary else c.surfaceContainerHigh, moTween(Mo.Normal), label = "track")
    val edge by animateColorAsState(if (checked) c.primary else c.outline, moTween(Mo.Normal), label = "edge")
    val thumbColor by animateColorAsState(if (checked) c.onPrimary else c.outline, moTween(Mo.Normal), label = "thumbC")
    val size by animateDpAsState(if (pressed) 28.dp else if (checked) 24.dp else 16.dp, moSpring(), label = "thumbS")
    val center by animateDpAsState(if (checked) 36.dp else 16.dp, moSpring(), label = "thumbX")
    Box(Modifier.size(52.dp, 32.dp).clip(CircleShape).background(track).border(2.dp, edge, CircleShape)) {
        Box(Modifier.offset(x = center - size / 2 - 2.dp, y = 14.dp - size / 2).size(size).clip(CircleShape).background(thumbColor))
    }
}

@Composable
internal fun SwitchRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit, icon: ImageVector? = null, enabled: Boolean = true) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val haptic = LocalHapticFeedback.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).alpha(if (enabled) 1f else 0.38f)
            .semantics { stateDescription = if (checked) "On" else "Off" }
            .toggleable(checked, enabled = enabled, role = Role.Switch, interactionSource = src, indication = ripple()) {
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(it)
            }
            .padding(horizontal = Sp.x4, vertical = Sp.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(Sp.x4)) }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Body(subtitle)
        }
        Spacer(Modifier.width(Sp.x3))
        AppSwitch(checked, pressed)
    }
}

@Composable
internal fun NavRow(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = Sp.x4, vertical = Sp.x3),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Body(value)
        }
        Icon(Icons.Rounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// ---------- status ----------
/** Pill with a dot and a text label. Colour fades, the label springs in on change, the dot pulses only while [pulse]. */
@Composable
internal fun StatusChip(label: String, color: Color, pulse: Boolean, description: String) {
    val reduced = LocalReduced.current
    val tint by animateColorAsState(color, moTween(Mo.Normal), label = "chip")
    val scale = remember { Animatable(1f) }
    LaunchedEffect(label) { if (!reduced) { scale.snapTo(0.9f); scale.animateTo(1f, spring(0.6f, Spring.StiffnessMedium)) } }
    val t = rememberInfiniteTransition(label = "pulse")
    val a by t.animateFloat(1f, 0.4f, infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Reverse), label = "dot")
    val rm = reduced
    Row(
        Modifier.graphicsLayer { scaleX = scale.value; scaleY = scale.value }
            .clip(CircleShape).background(tint.copy(alpha = 0.14f))
            .padding(horizontal = Sp.x3, vertical = Sp.x1 + 2.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite; contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).alpha(if (pulse && !reduced) a else 1f).clip(CircleShape).background(tint))
        Spacer(Modifier.width(Sp.x2))
        AnimatedContent(label, transitionSpec = { fadeIn(motion(rm, Mo.Normal)) togetherWith fadeOut(motion(rm, Mo.Fast)) }, label = "chipText") {
            Text(it, style = MaterialTheme.typography.labelLarge, color = tint)
        }
    }
}

// ---------- empty / loading ----------
@Composable
internal fun EmptyState(icon: ImageVector?, title: String, body: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    val reduced = LocalReduced.current
    val s = remember { Animatable(if (reduced) 1f else 0.6f) }
    LaunchedEffect(Unit) { if (!reduced) s.animateTo(1f, spring(0.6f, Spring.StiffnessMediumLow)) }
    Column(modifier.fillMaxWidth().padding(vertical = Sp.x8, horizontal = Sp.x4), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
        Box(Modifier.size(64.dp).graphicsLayer { scaleX = s.value; scaleY = s.value }.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center) {
            if (icon != null) Icon(icon, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary)
            else MacGlyph(MaterialTheme.colorScheme.primary, Modifier.size(28.dp))
        }
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        action?.invoke()
    }
}

/** Flat placeholder block that pulses between two surface levels (static when animations are off). */
@Composable
internal fun Skeleton(modifier: Modifier = Modifier, shape: androidx.compose.ui.graphics.Shape = MaterialTheme.shapes.small) {
    val reduced = LocalReduced.current
    val t = rememberInfiniteTransition(label = "skel")
    val a by t.animateFloat(0.5f, 1f, infiniteRepeatable(tween(900, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "skelA")
    Box(modifier.clip(shape).background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = if (reduced) 1f else a)))
}

@Composable
internal fun MacGlyph(tint: Color, modifier: Modifier = Modifier.size(24.dp)) {
    Canvas(modifier) {
        val w = size.width; val h = size.height; val sw = w * 0.09f
        drawRoundRect(tint, Offset(w * 0.14f, h * 0.18f), Size(w * 0.72f, h * 0.5f), CornerRadius(w * 0.07f),
            style = androidx.compose.ui.graphics.drawscope.Stroke(sw))
        drawRoundRect(tint, Offset(w * 0.04f, h * 0.76f), Size(w * 0.92f, h * 0.09f), CornerRadius(w * 0.05f))
    }
}
