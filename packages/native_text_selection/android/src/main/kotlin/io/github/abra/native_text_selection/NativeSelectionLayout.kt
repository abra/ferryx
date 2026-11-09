package io.github.abra.native_text_selection

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.LeadingMarginSpan
import android.text.style.LineHeightSpan
import android.text.style.ReplacementSpan
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

internal data class NativeCellAnchor(
    val nativeStart: Int,
    val nativeEnd: Int,
    val cell: SelectionCell,
)

internal data class NativeSelectionLayout(
    val text: SpannableStringBuilder,
    val offsets: SelectionOffsetMap,
    val anchors: List<NativeCellAnchor>,
    val originY: Double,
    val height: Int,
    val lineSpacing: Int,
) {
    fun nativeBoundary(
        sourceOffset: Int,
        end: Boolean,
    ): Int {
        val cluster = anchors.firstOrNull { sourceOffset > it.cell.start && sourceOffset < it.cell.end }
        if (cluster != null) return if (end) cluster.nativeEnd else cluster.nativeStart
        val exact =
            if (end) {
                anchors.lastOrNull { it.cell.end == sourceOffset }?.nativeEnd
            } else {
                anchors.firstOrNull { it.cell.start == sourceOffset }?.nativeStart
            }
        return exact ?: offsets.native(sourceOffset, trailing = !end)
    }

    companion object {
        fun build(
            source: String,
            lines: List<SelectionLine>,
            density: Double,
            width: Int,
            originX: Double,
        ): NativeSelectionLayout {
            val builder = SpannableStringBuilder()
            val mapped = mutableListOf(lines.first().start)
            val anchors = mutableListOf<NativeCellAnchor>()
            val margins = mutableListOf<NativeLineMargin>()
            val originY = lines.first().top
            val lineSpacing = SelectionGeometry.lineSpacing(lines, density)

            fun appendControl(
                character: Char,
                sourceOffset: Int,
            ) {
                builder.append(character)
                mapped.add(sourceOffset)
            }

            fun appendSource(
                start: Int,
                end: Int,
            ) {
                builder.append(source, start, end)
                for (offset in start + 1..end) mapped.add(offset)
            }

            for ((lineIndex, line) in lines.withIndex()) {
                val nativeLineStart = builder.length
                appendControl(if (line.rtl) '\u200f' else '\u200e', line.start)
                val top = ((line.top - originY) * density).roundToInt()
                val bottom = ((line.bottom - originY) * density).roundToInt()
                val lineHeight = max(1, bottom - top)
                var direction: Boolean? = null
                for ((index, cell) in line.cells.withIndex()) {
                    if (direction != cell.rtl) {
                        for (control in selectionDirectionControls(line.rtl, direction, cell.rtl)) {
                            appendControl(control, cell.start)
                        }
                        direction = cell.rtl
                    }
                    val next = line.cells.getOrNull(index + 1)
                    val leading = if (cell.rtl) cell.right else cell.left
                    val nextLeading = next?.let { if (it.rtl) it.right else it.left }
                    val advance =
                        if (next != null && next.rtl == cell.rtl && next.start == cell.end) {
                            abs((nextLeading!! * density).roundToInt() - (leading * density).roundToInt())
                        } else {
                            max(0, (cell.right * density).roundToInt() - (cell.left * density).roundToInt())
                        }
                    val nativeStart = builder.length
                    appendSource(cell.start, cell.end)
                    builder.setSpan(
                        GeometrySpan(advance, lineHeight),
                        nativeStart,
                        builder.length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    anchors.add(NativeCellAnchor(nativeStart, builder.length, cell))
                    if (next != null && next.start > cell.end) {
                        val gap = next.start - cell.end
                        if (source.substring(cell.end, next.start).any { it == '\n' || it == '\r' }) {
                            throw UnsupportedGeometry("Source line break has same-row geometry")
                        }
                        val trailing = if (cell.rtl) cell.left else cell.right
                        val gapWidth =
                            if (next.rtl == cell.rtl) {
                                max(0, abs((nextLeading!! * density).roundToInt() - (trailing * density).roundToInt()))
                            } else {
                                0
                            }
                        val gapStart = builder.length
                        appendSource(cell.end, cell.end + gap)
                        builder.setSpan(
                            GeometrySpan(gapWidth, lineHeight),
                            gapStart,
                            builder.length,
                            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
                }
                for (control in selectionDirectionControls(line.rtl, direction, null)) {
                    appendControl(control, line.end)
                }
                val nextLine = lines.getOrNull(lineIndex + 1)
                if (nextLine != null) appendControl('\n', line.end)
                val margin =
                    if (line.rtl) {
                        width - ((line.right - originX) * density).roundToInt()
                    } else {
                        ((line.left - originX) * density).roundToInt()
                    }
                if (margin < 0) throw UnsupportedGeometry("Text extends outside native region width")
                margins.add(NativeLineMargin(nativeLineStart, builder.length, margin))
                builder.setSpan(
                    ExactLineHeight(lineHeight),
                    nativeLineStart,
                    builder.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                if (nextLine != null) {
                    val gap = ((nextLine.top - originY) * density).roundToInt() - bottom - lineSpacing
                    if (gap > 0) {
                        val spacerStart = builder.length
                        appendControl('\u200b', line.end)
                        appendControl('\n', nextLine.start)
                        builder.setSpan(
                            ExactLineHeight(gap - lineSpacing),
                            spacerStart,
                            builder.length,
                            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    } else {
                        mapped[mapped.lastIndex] = nextLine.start
                    }
                }
            }
            // Paragraph spans set at a builder's current end grow with later appends.
            for (margin in margins) {
                builder.setSpan(
                    LeadingMarginSpan.Standard(margin.width),
                    margin.start,
                    margin.end,
                    Spannable.SPAN_PARAGRAPH,
                )
            }
            return NativeSelectionLayout(
                builder,
                SelectionOffsetMap(mapped.toIntArray()),
                anchors,
                originY,
                max(1, ((lines.last().bottom - originY) * density).roundToInt()),
                lineSpacing,
            )
        }
    }
}

private data class NativeLineMargin(
    val start: Int,
    val end: Int,
    val width: Int,
)

/** Only metrics are native: visible glyphs remain in the document renderer. */
private class GeometrySpan(
    private val width: Int,
    private val height: Int,
) : ReplacementSpan() {
    override fun getSize(
        paint: Paint,
        text: CharSequence,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?,
    ): Int {
        fm?.apply {
            ascent = -height
            top = -height
            descent = 0
            bottom = 0
            leading = 0
        }
        return width
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint,
    ) {
        // The Flutter surface already paints the original document glyphs.
    }
}

private class ExactLineHeight(
    private val height: Int,
) : LineHeightSpan {
    override fun chooseHeight(
        text: CharSequence,
        start: Int,
        end: Int,
        spanstartv: Int,
        v: Int,
        fm: Paint.FontMetricsInt,
    ) {
        fm.ascent = -height
        fm.top = -height
        fm.descent = 0
        fm.bottom = 0
        fm.leading = 0
    }
}
