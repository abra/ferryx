package io.github.abra.native_text_selection

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal data class SelectionCell(
    val start: Int,
    val end: Int,
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
    val rtl: Boolean,
) {
    val width: Double get() = right - left
    val height: Double get() = bottom - top
}

internal data class SelectionRegion(
    val start: Int,
    val end: Int,
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
)

internal data class SelectionLine(
    val cells: List<SelectionCell>,
) {
    val start: Int get() = cells.first().start
    val end: Int get() = cells.last().end
    val left: Double get() = cells.minOf { it.left }
    val top: Double get() = cells.minOf { it.top }
    val right: Double get() = cells.maxOf { it.right }
    val bottom: Double get() = cells.maxOf { it.bottom }
    val rtl: Boolean get() = cells.first().rtl
}

internal class UnsupportedGeometry(
    message: String,
) : IllegalArgumentException(message)

private class SelectionRow(first: SelectionCell) {
    val cells = mutableListOf(first)
    var top = first.top
        private set
    var bottom = first.bottom
        private set

    fun add(cell: SelectionCell) {
        cells.add(cell)
        top = min(top, cell.top)
        bottom = max(bottom, cell.bottom)
    }
}

/** Keep base runs at paragraph level; nesting them would reorder sibling runs. */
internal fun selectionDirectionControls(
    paragraphRtl: Boolean,
    previousRtl: Boolean?,
    nextRtl: Boolean?,
): String {
    if (previousRtl == nextRtl) return ""
    return buildString {
        if (previousRtl != null && previousRtl != paragraphRtl) append('\u202c')
        if (nextRtl != null && nextRtl != paragraphRtl) append(if (nextRtl) '\u202b' else '\u202a')
    }
}

/** Validates geometry before giving the native editor ownership of the range. */
internal object SelectionGeometry {
    fun lineSpacing(lines: List<SelectionLine>, density: Double): Int {
        if (lines.isEmpty()) return 0
        val origin = lines.first().top
        return lines.zipWithNext().minOfOrNull { (line, next) ->
            ((next.top - origin) * density).roundToInt() - ((line.bottom - origin) * density).roundToInt()
        }?.coerceAtMost(0) ?: 0
    }

    fun activeRegion(
        regions: List<SelectionRegion>,
        base: Int,
        extent: Int,
    ): SelectionRegion? {
        if (regions.isEmpty()) return null
        if (regions.any {
                it.start < 0 || it.end <= it.start ||
                    !it.left.isFinite() || !it.top.isFinite() ||
                    !it.right.isFinite() || !it.bottom.isFinite() ||
                    it.right <= it.left || it.bottom <= it.top
            }
        ) {
            throw UnsupportedGeometry("Invalid native page region")
        }
        val start = min(base, extent)
        val end = max(base, extent)
        return regions.firstOrNull { start >= it.start && end <= it.end }
            ?: throw UnsupportedGeometry("Selection crosses native page regions")
    }

    fun lines(
        text: String,
        boxes: List<SelectionCell>,
    ): List<SelectionLine> {
        if (boxes.isEmpty()) throw UnsupportedGeometry("No visible text geometry")
        val cells = boxes.sortedBy { it.start }
        val rows = mutableListOf<SelectionRow>()
        var previous: SelectionCell? = null
        for (cell in cells) {
            if (cell.start < 0 || cell.start >= cell.end || cell.end > text.length ||
                !cell.left.isFinite() || !cell.top.isFinite() ||
                !cell.right.isFinite() || !cell.bottom.isFinite() ||
                cell.width < 0 || cell.height <= 0
            ) {
                throw UnsupportedGeometry("Invalid text cell")
            }
            if (splitsSurrogate(text, cell.start) || splitsSurrogate(text, cell.end)) {
                throw UnsupportedGeometry("Text geometry splits a surrogate pair")
            }
            val last = previous
            if (last != null && cell.start < last.end) {
                throw UnsupportedGeometry("Overlapping source ranges")
            }
            if (last != null && cell.start > last.end &&
                text.substring(last.end, cell.start).any { !it.isWhitespace() && Character.getType(it) != Character.FORMAT.toInt() }
            ) {
                throw UnsupportedGeometry("Missing geometry for source text")
            }
            val row = rows.lastOrNull()
            if (row == null || !sameRow(row, cell)) {
                if (row != null && cell.top < row.top) {
                    throw UnsupportedGeometry("Text flow restarts vertically within a region")
                }
                rows.add(SelectionRow(cell))
            } else {
                row.add(cell)
            }
            previous = cell
        }
        return rows.map { row ->
            val visual = row.cells.sortedBy { it.left }
            for (i in 1 until visual.size) {
                if (visual[i].left < visual[i - 1].right - 1.0 &&
                    !hasOrderedAdjacentCarets(visual[i - 1], visual[i])
                ) {
                    val previous = visual[i - 1]
                    val next = visual[i]
                    throw UnsupportedGeometry(
                        "Overlapping visual text cells ${previous.start}..${previous.end}" +
                            " [${previous.left},${previous.top},${previous.right},${previous.bottom}] and " +
                            "${next.start}..${next.end} [${next.left},${next.top},${next.right},${next.bottom}]",
                    )
                }
            }
            SelectionLine(row.cells)
        }
    }

    private fun hasOrderedAdjacentCarets(left: SelectionCell, right: SelectionCell): Boolean {
        if (left.rtl != right.rtl) return false
        // Emoji and italic ink may overhang the following cell's advance.
        // The ordered source-adjacent leading edges still define exact carets.
        return if (left.rtl) {
            right.end == left.start && left.right < right.right
        } else {
            left.end == right.start && left.left < right.left
        }
    }

    private fun sameRow(
        row: SelectionRow,
        cell: SelectionCell,
    ): Boolean {
        val top = row.top
        val bottom = row.bottom
        val overlap = min(bottom, cell.bottom) - max(top, cell.top)
        return overlap >= min(bottom - top, cell.height) * 0.6 ||
            (abs(top - cell.top) < 0.5 && abs(bottom - cell.bottom) < 0.5)
    }

    private fun splitsSurrogate(
        text: String,
        offset: Int,
    ): Boolean =
        offset > 0 && offset < text.length &&
            Character.isHighSurrogate(text[offset - 1]) && Character.isLowSurrogate(text[offset])
}

/** Boundary map includes synthetic line breaks and directional controls. */
internal class SelectionOffsetMap(
    private val source: IntArray,
) {
    fun original(nativeOffset: Int): Int = source[nativeOffset.coerceIn(0, source.lastIndex)]

    fun native(
        originalOffset: Int,
        trailing: Boolean,
    ): Int {
        var low = 0
        var high = source.size
        while (low < high) {
            val middle = (low + high) ushr 1
            if (source[middle] < originalOffset || (trailing && source[middle] == originalOffset)) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return (if (trailing) low - 1 else low).coerceIn(0, source.lastIndex)
    }
}
