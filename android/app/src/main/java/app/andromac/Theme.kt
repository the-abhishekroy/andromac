package app.andromac

import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Brand {
    val Navy = Color(0xFF000000)
    val Navy2 = Color(0xFF0D0D0D)
    val Navy3 = Color(0xFF151515)
    val Green = Color(0xFF87D787)
    val Silver = Color(0xFFC8C8CC)
}

/** Status colours that always travel with an icon and a text label (never colour alone). */
@Immutable
class StatusColors(val ok: Color, val warn: Color, val bad: Color)

val LocalStatusColors = staticCompositionLocalOf { StatusColors(Brand.Green, Color(0xFFF5B942), Color(0xFFFF8A80)) }

private val DarkScheme = darkColorScheme(
    primary = Brand.Green, onPrimary = Color(0xFF000000),
    primaryContainer = Color(0xFF16301A), onPrimaryContainer = Color(0xFFD2F5D2),
    secondary = Brand.Silver, onSecondary = Color(0xFF121212),
    secondaryContainer = Color(0xFF2A2A2A), onSecondaryContainer = Color(0xFFF5F5F5),
    tertiary = Color(0xFF87AFFF), onTertiary = Color(0xFF000000),
    background = Color(0xFF000000), onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF000000), onSurface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFF151515), onSurfaceVariant = Color(0xFF8C8C8C),
    surfaceContainerLowest = Color(0xFF000000), surfaceContainerLow = Color(0xFF080808),
    surfaceContainer = Color(0xFF0D0D0D), surfaceContainerHigh = Color(0xFF151515),
    surfaceContainerHighest = Color(0xFF1E1E1E),
    outline = Color(0xFF7E7E7E), outlineVariant = Color(0xFF262626),
    error = Color(0xFFFF8A80), onError = Color(0xFF4A0600),
    errorContainer = Color(0xFF5C1A14), onErrorContainer = Color(0xFFFFDAD6),
    inverseSurface = Color(0xFFF5F5F5), inverseOnSurface = Color(0xFF121212), inversePrimary = Color(0xFF0B6B3A),
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF0A6B39), onPrimary = Color.White,
    primaryContainer = Color(0xFFC6F4D9), onPrimaryContainer = Color(0xFF00391B),
    secondary = Color(0xFF4A4A4A), onSecondary = Color.White,
    secondaryContainer = Color(0xFFE6E6E6), onSecondaryContainer = Color(0xFF111111),
    tertiary = Color(0xFF4A4A4A), onTertiary = Color.White,
    background = Color(0xFFF5F5F5), onBackground = Color(0xFF121212),
    surface = Color(0xFFFFFFFF), onSurface = Color(0xFF121212),
    surfaceVariant = Color(0xFFEBEBEB), onSurfaceVariant = Color(0xFF555555),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFAFAFA),
    surfaceContainer = Color(0xFFFFFFFF), surfaceContainerHigh = Color(0xFFF0F0F0),
    surfaceContainerHighest = Color(0xFFE6E6E6),
    outline = Color(0xFF767676), outlineVariant = Color(0xFFDADADA),
    error = Color(0xFFB3261E), onError = Color.White,
    errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
    inverseSurface = Color(0xFF121212), inverseOnSurface = Color(0xFFF5F5F5), inversePrimary = Brand.Green,
)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp), small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(20.dp), large = RoundedCornerShape(24.dp), extraLarge = RoundedCornerShape(28.dp),
)

private val Base = Typography()
private val AppTypography = Typography(
    headlineLarge = Base.headlineLarge.copy(fontWeight = FontWeight.Bold, fontSize = 32.sp, lineHeight = 40.sp),
    headlineMedium = Base.headlineMedium.copy(fontWeight = FontWeight.Bold, fontSize = 26.sp, lineHeight = 34.sp),
    headlineSmall = Base.headlineSmall.copy(fontWeight = FontWeight.Bold, fontSize = 23.sp, lineHeight = 30.sp),
    titleLarge = Base.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 28.sp),
    titleMedium = Base.titleMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 24.sp),
    titleSmall = Base.titleSmall.copy(fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge = Base.bodyLarge.copy(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = Base.bodyMedium.copy(fontSize = 14.sp, lineHeight = 21.sp),
    bodySmall = Base.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = Base.labelLarge.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = Base.labelMedium.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium, lineHeight = 16.sp),
)

@Composable
fun AndromacTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val status = if (dark) StatusColors(Brand.Green, Color(0xFFF5B942), Color(0xFFFF8A80))
    else StatusColors(Color(0xFF0A6B39), Color(0xFF8A5300), Color(0xFFB3261E))
    CompositionLocalProvider(LocalStatusColors provides status) {
        MaterialTheme(
            colorScheme = if (dark) DarkScheme else LightScheme,
            shapes = AppShapes, typography = AppTypography, content = content,
        )
    }
}

/** True when the user turned animations off in system settings. */
@Composable
fun rememberReducedMotion(): Boolean {
    val ctx = LocalContext.current
    return remember {
        runCatching { AndroidSettings.Global.getFloat(ctx.contentResolver, AndroidSettings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
            .getOrDefault(false)
    }
}
