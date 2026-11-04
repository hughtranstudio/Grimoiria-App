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
 * HT Press house style, A · Codex, on the Brand Codex. The palette (`Codex`) is generated into
 * CodexTokens.kt by App/tools/gen-tokens.py; this file only maps it onto Material.
 * Paper page by day, forest night after dark, Garamond everywhere, square corners; rubric red only for marks, green at night.
 */

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
    secondaryContainer = Codex.fogDay, onSecondaryContainer = Codex.ink,
    tertiary = Codex.rubricSmall, onTertiary = Codex.paper,
    error = Codex.rubricSmall, onError = Codex.paper,
    background = Codex.paper, onBackground = Codex.ink,
    surface = Codex.paper, onSurface = Codex.ink,
    surfaceVariant = Codex.mistDay, onSurfaceVariant = Codex.muted,
    surfaceContainerLowest = Codex.paper, surfaceContainerLow = Codex.vellum, surfaceContainer = Codex.vellum,
    surfaceContainerHigh = Codex.haze1Day, surfaceContainerHighest = Codex.haze2Day,
    outline = Codex.ink.copy(alpha = 0.55f), outlineVariant = Codex.ink.copy(alpha = 0.25f),
)

private val dark = darkColorScheme(
    primary = Codex.nightInk, onPrimary = Codex.nightGround,
    primaryContainer = Codex.nightSurface, onPrimaryContainer = Codex.nightInk,
    secondary = Codex.nightInk, onSecondary = Codex.nightGround,
    secondaryContainer = Codex.nightPanel2, onSecondaryContainer = Codex.nightInk,
    // The Codex at night: every red becomes a green of the same value.
    tertiary = Codex.nightRubric, onTertiary = Codex.nightGround,
    error = Codex.nightRubric, onError = Codex.nightGround,
    background = Codex.nightGround, onBackground = Codex.nightInk,
    surface = Codex.nightGround, onSurface = Codex.nightInk,
    surfaceVariant = Codex.nightSurface, onSurfaceVariant = Codex.nightMuted,
    surfaceContainerLowest = Codex.nightDeep, surfaceContainerLow = Codex.nightSurface, surfaceContainer = Codex.nightSurface,
    surfaceContainerHigh = Codex.nightPanel2, surfaceContainerHighest = Codex.nightLine,
    outline = Codex.nightInk.copy(alpha = 0.5f), outlineVariant = Codex.nightInk.copy(alpha = 0.28f),
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
    val extras = if (isDark) CodexExtras(Codex.nightInk.copy(alpha = 0.28f), Codex.nightRed, Codex.nightRubric, Codex.nightMuted)
    else CodexExtras(Codex.ink.copy(alpha = 0.25f), Codex.rubric, Codex.rubricSmall, Codex.muted)
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
