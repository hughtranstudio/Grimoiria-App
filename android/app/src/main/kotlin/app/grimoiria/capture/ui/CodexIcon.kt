package app.grimoiria.capture.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Hand-written. The icon data lives in the generated CodexIcons.kt (from Design/codex/icons.ts).

enum class CodexIconWeight { STROKE, HAIR, FILL }

/** One part of a Codex icon: SVG path data on the 24-unit grid. `detail` parts drop out in the caption cut. */
data class CodexIconPart(val weight: CodexIconWeight, val detail: Boolean, val d: String)

data class CodexIconDef(val name: String, val title: String, val parts: List<CodexIconPart>)

/** The optical cut for a size, as the Codex icon scale defines it. */
data class CodexIconCut(val caption: Boolean, val stroke: Float, val hair: Float) {
    companion object {
        fun at(size: Float): CodexIconCut = with(CodexIcons.Scale) {
            when {
                size <= captionTo -> CodexIconCut(true, captionStroke, captionHair)
                size <= textTo -> CodexIconCut(false, textStroke, textHair)
                else -> CodexIconCut(false, displayStroke, displayHair)
            }
        }
    }
}

/**
 * Draws a Codex icon in the current content colour. Strokes keep their weight in real dp at
 * every size (round caps and joins); fills use the even-odd rule, like the site.
 */
@Composable
fun CodexIcon(
    icon: CodexIconDef,
    modifier: Modifier = Modifier,
    size: Dp = CodexIcons.Scale.lg.dp,
    tint: Color = LocalContentColor.current,
    contentDescription: String? = null,
) {
    val cut = CodexIconCut.at(size.value)
    val paths = remember(icon, cut.caption) {
        icon.parts.filter { !(cut.caption && it.detail) }.map { part ->
            val path: Path = PathParser().parsePathString(part.d).toPath()
            if (part.weight == CodexIconWeight.FILL) path.fillType = PathFillType.EvenOdd
            part.weight to path
        }
    }
    val described = if (contentDescription != null) modifier.semantics { this.contentDescription = contentDescription } else modifier
    Canvas(described.size(size)) {
        val k = this.size.width / 24f
        scale(k, k, pivot = Offset.Zero) {
            for ((weight, path) in paths) {
                when (weight) {
                    CodexIconWeight.FILL -> drawPath(path, tint, style = Fill)
                    else -> {
                        val w = if (weight == CodexIconWeight.STROKE) cut.stroke else cut.hair
                        drawPath(path, tint, style = Stroke(width = w.dp.toPx() / k, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    }
                }
            }
        }
    }
}
