// Shared look: Runway ink + white opacity ladder, one ember accent, ABC Normal (port of components/ui.brs).
// Everything is laid out on a 1920x1080 design canvas: AppUi rescales density so 1.dp == 1 design pixel.
package com.npetillo.fedsmokertv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.npetillo.fedsmokertv.R
import com.npetillo.fedsmokertv.hasNonLatin

object P {
    val ink = Color(0xFF0C0C0C)
    val w100 = Color(0xFFFFFFFF)
    val w85 = Color(0xD9FFFFFF)
    val w60 = Color(0x99FFFFFF)
    val w35 = Color(0x59FFFFFF)
    val w20 = Color(0x33FFFFFF)
    val w15 = Color(0x26FFFFFF)
    val w12 = Color(0x1FFFFFFF)
    val w10 = Color(0x1AFFFFFF)
    val w08 = Color(0x14FFFFFF)
    val w06 = Color(0x0FFFFFFF)
    val w05 = Color(0x0DFFFFFF)
    val ink85 = Color(0xD90C0C0C)
    val ink75 = Color(0xBF0C0C0C)
    val ink70 = Color(0xB30C0C0C)
    val ink60 = Color(0x990C0C0C)
    val ink50 = Color(0x800C0C0C)
    val ink08 = Color(0x140C0C0C)
    val ember = Color(0xFFB35A45)
    val emberLight = Color(0xFFD78A6A)
}

val Abc = FontFamily(
    Font(R.font.abc_normal, FontWeight.Normal),
    Font(R.font.abc_regular, FontWeight.Medium),
)

/** Absolute position on the design canvas. */
fun Modifier.at(x: Int, y: Int) = this.offset(x.dp, y.dp)

fun Modifier.box(w: Int, h: Int) = this.size(w.dp, h.dp)

fun Modifier.rounded(color: Color, r: Int) = this.background(color, RoundedCornerShape(r.dp))

fun Modifier.outline(color: Color, r: Int, w: Int = 1) = this.border(w.dp, color, RoundedCornerShape(r.dp))

/**
 * A single- or multi-line label. ABC Normal has no Arabic/Cyrillic/Greek/Hebrew, so text with
 * characters above U+024F uses the system font instead.
 */
@Composable
fun Txt(
    text: String,
    size: Int,
    color: Color,
    modifier: Modifier = Modifier,
    medium: Boolean = false,
    maxLines: Int = 1,
    align: TextAlign = TextAlign.Start,
    lineSpacing: Int = 0,
) {
    BasicText(
        text = text,
        modifier = modifier,
        style = TextStyle(
            color = color,
            fontSize = size.sp,
            fontFamily = if (hasNonLatin(text)) FontFamily.Default else Abc,
            fontWeight = if (medium) FontWeight.Medium else FontWeight.Normal,
            textAlign = align,
            lineHeight = if (lineSpacing > 0) (size * 1.2f + lineSpacing).sp else TextUnit.Unspecified,
            platformStyle = PlatformTextStyle(includeFontPadding = false),
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
        ),
        maxLines = maxLines,
        softWrap = maxLines > 1,
        overflow = TextOverflow.Ellipsis,
    )
}

/** Text vertically centred in a fixed-height row. */
@Composable
fun RowTxt(text: String, size: Int, color: Color, h: Int, modifier: Modifier = Modifier, align: TextAlign = TextAlign.Start, medium: Boolean = false) {
    Box(modifier.height(h.dp), contentAlignment = if (align == TextAlign.End) Alignment.CenterEnd else if (align == TextAlign.Center) Alignment.Center else Alignment.CenterStart) {
        Txt(text, size, color, align = align, medium = medium)
    }
}

@Composable
fun Dot(size: Int = 10, color: Color = P.ember, modifier: Modifier = Modifier) {
    Box(modifier.box(size, size).rounded(color, size / 2))
}

/** Rounded button: outline when idle, solid white with ink text when focused. Height 72. */
@Composable
fun PillButton(text: String, focused: Boolean, modifier: Modifier = Modifier) {
    val m = if (focused) modifier.rounded(P.w100, 36) else modifier.outline(P.w60, 36)
    Box(m.height(72.dp).padding(horizontal = 44.dp), contentAlignment = Alignment.Center) {
        Txt(text, 26, if (focused) P.ink else P.w100)
    }
}

/** Footer row of remote-key hints: [key cap] label. */
@Composable
fun KeyHints(hints: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    Row(modifier.height(72.dp), verticalAlignment = Alignment.CenterVertically) {
        hints.forEachIndexed { i, (k, t) ->
            if (i > 0) Spacer(Modifier.width(40.dp))
            Box(Modifier.height(28.dp).outline(P.w35, 6).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                Txt(k, 16, P.w60)
            }
            Spacer(Modifier.width(12.dp))
            Txt(t, 20, P.w60)
        }
    }
}
