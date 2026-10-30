package app.grimoiria.capture.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.grimoiria.capture.R

/**
 * HT Press house style, A · Codex (App/Design/tokens.json on the Mac branch): vellum page, ink type,
 * Garamond everywhere, square corners, rubric red only for marks. Dark mode is ink and linen.
 */
object Codex {
    val ink = Color(0xFF000000)
    val soot = Color(0xFF141414)
    val paper = Color(0xFFFFFFFF)
    val vellum = Color(0xFFF8F8F8)
    val linen = Color(0xFFF4F4F4)
    val muted = Color(0xFF6B6B6B)
    val rubric = Color(0xFFEB0303)
    /** Red text under 24 pt on light grounds. */
    val rubricSmall = Color(0xFFCC0000)
    val rubricOnDark = Color(0xFFFF3232)
}

@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
private fun weighted(res: Int, weight: Int, style: FontStyle = FontStyle.Normal) =
    Font(res, FontWeight(weight), style, variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

val TitleFamily = FontFamily(
    weighted(R.font.cormorant_garamond, 500),
    weighted(R.font.cormorant_garamond, 600),
    weighted(R.font.cormorant_garamond, 700),
)
val TextFamily = FontFamily(
    weighted(R.font.eb_garamond, 400),
    weighted(R.font.eb_garamond, 500),
    weighted(R.font.eb_garamond, 600),
    weighted(R.font.eb_garamond_italic, 400, FontStyle.Italic),
)

/** Colours Material has no slot for. */
@Immutable
data class CodexExtras(val rule: Color, val rubric: Color, val rubricText: Color, val muted: Color)

val LocalCodex = staticCompositionLocalOf { CodexExtras(Codex.ink.copy(alpha = 0.14f), Codex.rubric, Codex.rubricSmall, Codex.muted) }

private val light = lightColorScheme(
    primary = Codex.ink, onPrimary = Codex.paper,
    primaryContainer = Codex.paper, onPrimaryContainer = Codex.ink,
    secondary = Codex.ink, onSecondary = Codex.paper,
    secondaryContainer = Color(0xFFEDEDED), onSecondaryContainer = Codex.ink,
    tertiary = Codex.rubricSmall, onTertiary = Codex.paper,
    error = Codex.rubricSmall, onError = Codex.paper,
    background = Codex.vellum, onBackground = Codex.ink,
    surface = Codex.vellum, onSurface = Codex.ink,
    surfaceVariant = Color(0xFFEFEFEF), onSurfaceVariant = Codex.muted,
    surfaceContainerLowest = Codex.paper, surfaceContainerLow = Codex.paper, surfaceContainer = Codex.paper,
    surfaceContainerHigh = Color(0xFFF1F1F1), surfaceContainerHighest = Color(0xFFEAEAEA),
    outline = Codex.ink.copy(alpha = 0.55f), outlineVariant = Codex.ink.copy(alpha = 0.14f),
)

private val dark = darkColorScheme(
    primary = Codex.linen, onPrimary = Codex.ink,
    primaryContainer = Codex.soot, onPrimaryContainer = Codex.linen,
    secondary = Codex.linen, onSecondary = Codex.ink,
    secondaryContainer = Color(0xFF242424), onSecondaryContainer = Codex.linen,
    tertiary = Codex.rubricOnDark, onTertiary = Codex.ink,
    error = Codex.rubricOnDark, onError = Codex.ink,
    background = Codex.ink, onBackground = Codex.linen,
    surface = Codex.ink, onSurface = Codex.linen,
    surfaceVariant = Codex.soot, onSurfaceVariant = Codex.linen.copy(alpha = 0.62f),
    surfaceContainerLowest = Codex.ink, surfaceContainerLow = Codex.soot, surfaceContainer = Codex.soot,
    surfaceContainerHigh = Color(0xFF1C1C1C), surfaceContainerHighest = Color(0xFF242424),
    outline = Codex.linen.copy(alpha = 0.5f), outlineVariant = Codex.linen.copy(alpha = 0.16f),
)

private fun typography(): Typography {
    val base = Typography()
    fun text(s: TextStyle, size: Int) = s.copy(fontFamily = TextFamily, fontSize = size.sp)
    // Titles: Cormorant in small capitals' spirit, tracked out as on the Mac.
    fun title(s: TextStyle, size: Int) = s.copy(fontFamily = TitleFamily, fontWeight = FontWeight.SemiBold, fontSize = size.sp, letterSpacing = 0.06.em)
    return Typography(
        displayLarge = title(base.displayLarge, 48), displayMedium = title(base.displayMedium, 40), displaySmall = title(base.displaySmall, 34),
        headlineLarge = title(base.headlineLarge, 32), headlineMedium = title(base.headlineMedium, 28), headlineSmall = title(base.headlineSmall, 25),
        titleLarge = title(base.titleLarge, 24), titleMedium = title(base.titleMedium, 19), titleSmall = title(base.titleSmall, 17),
        bodyLarge = text(base.bodyLarge, 18), bodyMedium = text(base.bodyMedium, 16), bodySmall = text(base.bodySmall, 14),
        labelLarge = text(base.labelLarge, 16).copy(fontWeight = FontWeight.Medium),
        labelMedium = text(base.labelMedium, 14).copy(fontWeight = FontWeight.Medium),
        labelSmall = text(base.labelSmall, 12).copy(fontWeight = FontWeight.Medium),
    )
}

@Composable
fun CaptureTheme(content: @Composable () -> Unit) {
    val isDark = isSystemInDarkTheme()
    val extras = if (isDark) CodexExtras(Codex.linen.copy(alpha = 0.16f), Codex.rubricOnDark, Codex.rubricOnDark, Codex.linen.copy(alpha = 0.62f))
    else CodexExtras(Codex.ink.copy(alpha = 0.14f), Codex.rubric, Codex.rubricSmall, Codex.muted)
    val corner = RoundedCornerShape(2.dp)
    androidx.compose.runtime.CompositionLocalProvider(LocalCodex provides extras) {
        MaterialTheme(
            colorScheme = if (isDark) dark else light,
            typography = typography(),
            shapes = Shapes(extraSmall = corner, small = corner, medium = corner, large = corner, extraLarge = corner),
            content = content,
        )
    }
}
