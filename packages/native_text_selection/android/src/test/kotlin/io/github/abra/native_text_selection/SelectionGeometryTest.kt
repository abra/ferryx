package io.github.abra.native_text_selection

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.text.Bidi

class SelectionGeometryTest {
    @Test
    fun mixedRtlRunsKeepTheirNativeBidiLevelsAndVisualOrder() {
        val directions = listOf(true, true, false, false, true, true)
        val text = StringBuilder("\u200f")
        val offsets = mutableListOf<Int>()
        var previous: Boolean? = null
        for (rtl in directions) {
            text.append(selectionDirectionControls(true, previous, rtl))
            offsets.add(text.length)
            // Android substitutes every ReplacementSpan with this neutral cell.
            text.append('\ufffc')
            previous = rtl
        }
        text.append(selectionDirectionControls(true, previous, null))
        val bidi = Bidi(text.toString(), Bidi.DIRECTION_RIGHT_TO_LEFT)
        val levels = offsets.map { bidi.getLevelAt(it).toByte() }.toByteArray()
        assertEquals(listOf<Byte>(1, 1, 2, 2, 1, 1), levels.toList())
        val order: Array<Any> = Array(directions.size) { it }
        Bidi.reorderVisually(levels, 0, order, 0, order.size)
        assertEquals(listOf(5, 4, 2, 3, 1, 0), order.toList())
    }

    @Test
    fun arabicInsideLtrUsesOneEmbeddingLevel() {
        val text = "\u200e\ufffc" + selectionDirectionControls(false, false, true) + "\ufffc" +
            selectionDirectionControls(false, true, false) + "\ufffc"
        val bidi = Bidi(text, Bidi.DIRECTION_LEFT_TO_RIGHT)
        assertEquals(0, bidi.getLevelAt(1))
        assertEquals(1, bidi.getLevelAt(3))
        assertEquals(0, bidi.getLevelAt(5))
    }

    @Test
    fun groupsLogicalCharactersIntoVisualLines() {
        val lines =
            SelectionGeometry.lines(
                "ab cd",
                listOf(cell(0, 1, 0.0, 0.0), cell(1, 2, 10.0, 0.0), cell(3, 4, 0.0, 20.0), cell(4, 5, 10.0, 20.0)),
            )
        assertEquals(listOf(0, 3), lines.map { it.start })
        assertEquals(listOf(2, 5), lines.map { it.end })
    }

    @Test
    fun preservesRtlSourceOrder() {
        val lines =
            SelectionGeometry.lines(
                "אב",
                listOf(cell(0, 1, 10.0, 0.0, rtl = true), cell(1, 2, 0.0, 0.0, rtl = true)),
            )
        assertEquals(listOf(0, 1), lines.single().cells.map { it.start })
        assertEquals(true, lines.single().rtl)
    }

    @Test
    fun acceptsPartiallyVisibleLines() {
        val lines = SelectionGeometry.lines("ab", listOf(cell(0, 1, 0.0, -5.0), cell(1, 2, 10.0, -5.0)))
        assertEquals(-5.0, lines.single().top, 0.0)
    }

    @Test
    fun usesNegativeNativeLineSpacingForOverlappingArabicFontCells() {
        val lines = SelectionGeometry.lines(
            "ab",
            listOf(
                SelectionCell(0, 1, 0.0, 10.0, 10.0, 54.0, true),
                SelectionCell(1, 2, 0.0, 44.0, 10.0, 88.0, true),
            ),
        )
        assertEquals(-30, SelectionGeometry.lineSpacing(lines, 3.0))
    }

    @Test
    fun ordinaryLineGapsDoNotNeedNegativeSpacing() {
        val lines = SelectionGeometry.lines("ab", listOf(cell(0, 1, 0.0, 0.0), cell(1, 2, 0.0, 20.0)))
        assertEquals(0, SelectionGeometry.lineSpacing(lines, 3.0))
    }

    @Test
    fun acceptsUnpaintedDirectionalControls() {
        val lines = SelectionGeometry.lines("a\u200eb", listOf(cell(0, 1, 0.0, 0.0), cell(2, 3, 10.0, 0.0)))
        assertEquals(3, lines.single().end)
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsInvalidPageBounds() {
        SelectionGeometry.activeRegion(listOf(SelectionRegion(0, 20, Double.NaN, 0.0, 100.0, 100.0)), 0, 10)
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsMissingNonWhitespaceSource() {
        SelectionGeometry.lines("abc", listOf(cell(0, 1, 0.0, 0.0), cell(2, 3, 10.0, 0.0)))
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsSurrogateSplitting() {
        SelectionGeometry.lines("😀", listOf(cell(0, 1, 0.0, 0.0), cell(1, 2, 10.0, 0.0)))
    }

    @Test
    fun acceptsWholeSurrogateCluster() {
        assertEquals(2, SelectionGeometry.lines("😀", listOf(cell(0, 2, 0.0, 0.0))).single().end)
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsNativeFlowRestarts() {
        SelectionGeometry.lines("abc", listOf(cell(0, 1, 0.0, 0.0), cell(1, 2, 0.0, 20.0), cell(2, 3, 50.0, 0.0)))
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsAmbiguousOverlappingCells() {
        SelectionGeometry.lines("ab", listOf(cell(0, 1, 0.0, 0.0), cell(1, 2, 0.0, 0.0)))
    }

    @Test
    fun acceptsOverhangingEmojiInkBeforeWhitespaceAdvance() {
        val lines = SelectionGeometry.lines(
            "😀 ",
            listOf(
                SelectionCell(0, 2, 0.0, 0.0, 30.0, 28.0, false),
                SelectionCell(2, 3, 25.0, 0.0, 31.0, 28.0, false),
            ),
        )
        assertEquals(2, lines.single().cells.size)
    }

    @Test
    fun choosesTheSelectedPhysicalPage() {
        val regions = listOf(region(0, 20), region(20, 40))
        assertEquals(regions[1], SelectionGeometry.activeRegion(regions, 30, 25))
        assertEquals(regions[0], SelectionGeometry.activeRegion(regions, 0, 20))
        assertNull(SelectionGeometry.activeRegion(emptyList(), 0, 10))
    }

    @Test(expected = UnsupportedGeometry::class)
    fun rejectsCrossPageRanges() {
        SelectionGeometry.activeRegion(listOf(region(0, 20), region(20, 40)), 10, 30)
    }

    @Test
    fun mapsSyntheticVisualBreaksToOriginalOffsets() {
        val mapping = SelectionOffsetMap(intArrayOf(10, 10, 11, 12, 12, 15, 15, 16))
        assertEquals(12, mapping.original(4))
        assertEquals(15, mapping.original(5))
        assertEquals(3, mapping.native(12, trailing = false))
        assertEquals(4, mapping.native(12, trailing = true))
        assertEquals(5, mapping.native(14, trailing = false))
        assertEquals(4, mapping.native(14, trailing = true))
        assertEquals(10, mapping.original(-1))
        assertEquals(16, mapping.original(100))
    }

    private fun cell(
        start: Int,
        end: Int,
        x: Double,
        y: Double,
        rtl: Boolean = false,
    ) = SelectionCell(start, end, x, y, x + 10.0, y + 12.0, rtl)

    private fun region(
        start: Int,
        end: Int,
    ) = SelectionRegion(start, end, 0.0, 0.0, 100.0, 200.0)
}
