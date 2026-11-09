package io.github.abra.native_text_selection

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.Selection
import android.text.Spannable
import android.util.Log
import android.view.ActionMode
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal class NativeSelectionSurface(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    arguments: Map<*, *>?,
) : PlatformView,
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "${NativeTextSelectionPlugin.VIEW_TYPE}/$viewId")
    private val density =
        context.resources.displayMetrics.density
            .toDouble()
    private val container = FrameLayout(context)
    private val editor = SelectionTextView(context)
    private var snapshot: Snapshot? = null
    private var nativeLayout: NativeSelectionLayout? = null
    private var actionMode: ActionMode? = null
    private var pendingRange: Pair<Int, Int>? = null
    private var activeRegion: SelectionRegion? = null
    private var suppressed = true
    private var disposed = false
    private var adjusting = false
    private var hasQueuedSelection = false
    private var requestedRange: Pair<Int, Int>? = null
    private var unsupportedRevision: Int? = null
    private var layoutValidated = false

    private val emitSelection =
        Runnable {
            hasQueuedSelection = false
            flushSelection()
        }
    private val finishAdjustment =
        Runnable {
            flushSelection()
            setAdjusting(false)
        }

    init {
        container.clipChildren = true
        container.clipToPadding = true
        container.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        editor.apply {
            setBackgroundColor(Color.TRANSPARENT)
            setTextColor(Color.TRANSPARENT)
            setTextIsSelectable(true)
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            gravity = Gravity.TOP or Gravity.START
            setHorizontallyScrolling(false)
            setLineSpacing(0f, 1f)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, 1f)
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            isSaveEnabled = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                setTextClassifier(android.view.textclassifier.TextClassifier.NO_OP)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isFallbackLineSpacing = false
            customSelectionActionModeCallback = NativeActionModeCallback()
            onRangeChanged = ::selectionChanged
            onContextAction = ::contextAction
            onTouchState = { active ->
                if (active) {
                    setAdjusting(true)
                } else {
                    editor.removeCallbacks(finishAdjustment)
                    finishAdjustment.run()
                }
            }
        }
        container.addView(editor, FrameLayout.LayoutParams(1, 1))
        container.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) rebuild()
        }
        channel.setMethodCallHandler(this)
        if (arguments != null) update(arguments)
    }

    override fun getView(): View = container

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (disposed) {
            result.error("disposed", "Selection surface has been disposed", null)
            return
        }
        try {
            when (call.method) {
                "update" -> {
                    update(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(true)
                }

                "select" -> {
                    val base = call.argument<Number>("base")?.toInt()
                    val extent = call.argument<Number>("extent")?.toInt()
                    if (base == null || extent == null) {
                        result.error("invalid_arguments", "Selection offsets are required", null)
                    } else {
                        requestedRange = base to extent
                        if (nativeLayout == null) rebuild() else applyRequestedRange()
                        result.success(null)
                    }
                }

                "clear" -> {
                    requestedRange = null
                    clear()
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (error: IllegalArgumentException) {
            result.error("invalid_arguments", error.message, null)
        }
    }

    private fun update(arguments: Map<*, *>) {
        val next = Snapshot.parse(arguments)
        val old = snapshot
        if (old?.revision != next.revision) {
            flushSelection()
            setAdjusting(false)
            editor.removeCallbacks(emitSelection)
            editor.removeCallbacks(finishAdjustment)
            hasQueuedSelection = false
            suppressed = true
            actionMode?.finish()
            actionMode = null
            (editor.text as? Spannable)?.let { Selection.removeSelection(it) }
        }
        snapshot = next
        requestedRange = next.selection
        if (old != null && old.text == next.text && old.boxes == next.boxes && old.regions == next.regions &&
            nativeLayout != null && unsupportedRevision != next.revision
        ) {
            updateColors(next)
            applyRequestedRange()
        } else {
            rebuild()
        }
    }

    private fun rebuild() {
        val current = snapshot ?: return
        val range = requestedRange ?: return clear()
        if (disposed || container.width <= 0 || container.height <= 0) return
        try {
            if (current.editable) {
                throw UnsupportedGeometry("Editable fields retain Flutter focus and input selection")
            }
            if (min(range.first, range.second) < 0 || max(range.first, range.second) > current.text.length) {
                throw UnsupportedGeometry("Invalid source selection range")
            }
            val region =
                SelectionGeometry.activeRegion(current.regions, range.first, range.second)
                    ?: SelectionRegion(0, current.text.length, 0.0, 0.0, container.width / density, container.height / density)
            val cells = current.boxes.filter { it.start >= region.start && it.end <= region.end }
            val lines = SelectionGeometry.lines(current.text, cells)
            val width = max(1, ((region.right - region.left) * density).roundToInt())
            val layout = NativeSelectionLayout.build(current.text, lines, density, width, region.left)
            if (layout.lineSpacing < 0 && Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                throw UnsupportedGeometry("Overlapping font cells require Android 14 native caret metrics")
            }
            activeRegion = region
            suppressed = true
            layoutValidated = false
            nativeLayout = layout
            editor.setLineSpacing(layout.lineSpacing.toFloat(), 1f)
            editor.setText(layout.text, TextView.BufferType.SPANNABLE)
            editor.layoutParams =
                FrameLayout.LayoutParams(width, layout.height).apply {
                    leftMargin = (region.left * density).roundToInt()
                    topMargin = (layout.originY * density).roundToInt()
                }
            updateColors(current)
            editor.post {
                if (disposed || nativeLayout !== layout || snapshot?.revision != current.revision) return@post
                try {
                    validateNativeLayout(layout, region)
                    unsupportedRevision = null
                    layoutValidated = true
                    suppressed = false
                    applyRequestedRange()
                } catch (error: UnsupportedGeometry) {
                    unsupported(error.message ?: "Unsupported native text layout")
                }
            }
        } catch (error: UnsupportedGeometry) {
            unsupported(error.message ?: "Unsupported native text geometry")
        }
    }

    private fun validateNativeLayout(
        geometry: NativeSelectionLayout,
        region: SelectionRegion,
    ) {
        val layout = editor.layout ?: throw UnsupportedGeometry("Native layout was not created")
        // Native cells use integer pixels; reject drift rather than putting handles on another glyph.
        val tolerance = max(1.5, density)
        for (anchor in geometry.anchors) {
            val line = layout.getLineForOffset(anchor.nativeStart)
            val isRtlParagraph = layout.getParagraphDirection(line) == -1
            val start = if (layout.isRtlCharAt(anchor.nativeStart) != isRtlParagraph) {
                layout.getSecondaryHorizontal(anchor.nativeStart).toDouble()
            } else {
                layout.getPrimaryHorizontal(anchor.nativeStart).toDouble()
            }
            val expected = ((if (anchor.cell.rtl) anchor.cell.right else anchor.cell.left) - region.left) * density
            val top = layout.getLineTop(line) + geometry.originY * density
            val lineBottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                layout.getLineBottom(line, false)
            } else {
                layout.getLineBottom(line)
            }
            val bottom = lineBottom + geometry.originY * density
            if (abs(start - expected) > tolerance ||
                top > anchor.cell.top * density + tolerance ||
                bottom < anchor.cell.bottom * density - tolerance
            ) {
                throw UnsupportedGeometry(
                    "Native editor geometry mismatch at ${anchor.cell.start}: " +
                        "x=$start expected=$expected top=$top bottom=$bottom " +
                        "expectedTop=${anchor.cell.top * density} expectedBottom=${anchor.cell.bottom * density}",
                )
            }
        }
    }

    private fun updateColors(current: Snapshot) {
        editor.highlightColor = current.selectionColor
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            editor.textSelectHandleLeft?.mutate()?.setTint(current.accent)
            editor.textSelectHandleRight?.mutate()?.setTint(current.accent)
            editor.textSelectHandle?.mutate()?.setTint(current.accent)
        }
        actionMode?.invalidate()
    }

    private fun applyRequestedRange() {
        val geometry = nativeLayout ?: return
        val range = requestedRange ?: return clear()
        val current = snapshot ?: return
        if (unsupportedRevision == current.revision || !layoutValidated) return
        val start = min(range.first, range.second)
        val end = max(range.first, range.second)
        if (start < 0 || end > current.text.length) return unsupported("Invalid source selection range")
        if (start == end) return clear()
        try {
            val region = SelectionGeometry.activeRegion(current.regions, start, end)
            if (region != null && region != activeRegion) return rebuild()
        } catch (error: UnsupportedGeometry) {
            return unsupported(error.message ?: "Selection crosses native page regions")
        }
        val nativeStart = geometry.nativeBoundary(start, end = false)
        val nativeEnd = geometry.nativeBoundary(end, end = true)
        if (editor.selectionStart == nativeStart && editor.selectionEnd == nativeEnd && actionMode != null) {
            notifyReady()
            return
        }
        suppressed = true
        if (editor.selectionStart == nativeStart && editor.selectionEnd == nativeEnd) {
            (editor.text as? Spannable)?.let { Selection.removeSelection(it) }
        }
        val selectionArguments =
            Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, nativeStart)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, nativeEnd)
            }
        val accepted = editor.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectionArguments)
        suppressed = false
        if (!accepted) unsupported("Native editor did not accept the requested range")
    }

    private fun selectionChanged(
        start: Int,
        end: Int,
    ) {
        if (suppressed || disposed) return
        val geometry = nativeLayout ?: return
        val originalStart = if (start < 0) -1 else geometry.offsets.original(start)
        val originalEnd = if (end < 0) -1 else geometry.offsets.original(end)
        pendingRange = originalStart to originalEnd
        requestedRange = pendingRange
        setAdjusting(true)
        if (!hasQueuedSelection) {
            hasQueuedSelection = true
            editor.postOnAnimation(emitSelection)
        }
        // Android's handle PopupWindows do not expose public drag lifecycle callbacks.
        editor.removeCallbacks(finishAdjustment)
        editor.postDelayed(finishAdjustment, 120L)
    }

    private fun flushSelection() {
        val range = pendingRange ?: return
        pendingRange = null
        val current = snapshot ?: return
        if (!disposed) {
            channel.invokeMethod(
                "selectionChanged",
                mapOf("revision" to current.revision, "base" to range.first, "extent" to range.second),
            )
        }
    }

    private fun setAdjusting(value: Boolean) {
        if (disposed || suppressed || adjusting == value) return
        if (!value) flushSelection()
        adjusting = value
        channel.invokeMethod("adjusting", mapOf("revision" to snapshot?.revision, "value" to value))
    }

    private fun copyOriginalSelection(): Boolean {
        val current = snapshot ?: return false
        val geometry = nativeLayout ?: return false
        val start = geometry.offsets.original(min(editor.selectionStart, editor.selectionEnd))
        val end = geometry.offsets.original(max(editor.selectionStart, editor.selectionEnd))
        if (start >= end) return false
        val clipboard = editor.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(null, current.text.substring(start, end)))
        channel.invokeMethod("action", mapOf("revision" to current.revision, "action" to "copy", "base" to start, "extent" to end))
        return true
    }

    private fun contextAction(id: Int): Boolean {
        val current = snapshot ?: return false
        val action =
            when (id) {
                android.R.id.copy -> "copy"
                android.R.id.selectAll -> "selectAll"
                else -> return false
            }
        if (id == android.R.id.copy) return copyOriginalSelection()
        channel.invokeMethod("action", mapOf("revision" to current.revision, "action" to action))
        return true
    }

    private fun unsupported(reason: String) {
        val revision = snapshot?.revision ?: return
        unsupportedRevision = revision
        layoutValidated = false
        clear()
        Log.w("NativeTextSelection", reason)
        channel.invokeMethod("unsupportedGeometry", mapOf("revision" to revision, "reason" to reason))
    }

    private fun notifyReady() {
        val current = snapshot ?: return
        if (!disposed && layoutValidated && unsupportedRevision != current.revision) {
            suppressed = false
            channel.invokeMethod("ready", mapOf("revision" to current.revision))
        }
    }

    private fun clear() {
        suppressed = true
        editor.removeCallbacks(emitSelection)
        editor.removeCallbacks(finishAdjustment)
        hasQueuedSelection = false
        pendingRange = null
        actionMode?.finish()
        actionMode = null
        (editor.text as? Spannable)?.let { Selection.removeSelection(it) }
        editor.clearFocus()
        if (adjusting && !disposed) {
            adjusting = false
            channel.invokeMethod("adjusting", mapOf("revision" to snapshot?.revision, "value" to false))
        }
        suppressed = false
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        clear()
        editor.onRangeChanged = null
        editor.onContextAction = null
        editor.onTouchState = null
        nativeLayout = null
        snapshot = null
        channel.setMethodCallHandler(null)
        container.removeAllViews()
    }

    private inner class NativeActionModeCallback : ActionMode.Callback {
        override fun onCreateActionMode(
            mode: ActionMode,
            menu: Menu,
        ): Boolean {
            actionMode = mode
            configureMenu(menu)
            editor.post { if (actionMode === mode) notifyReady() }
            return true
        }

        override fun onPrepareActionMode(
            mode: ActionMode,
            menu: Menu,
        ): Boolean {
            configureMenu(menu)
            return true
        }

        private fun configureMenu(menu: Menu) {
            if (snapshot?.showMenu != true) {
                menu.clear()
                return
            }
            for (index in menu.size() - 1 downTo 0) {
                val item = menu.getItem(index)
                if (item.itemId != android.R.id.copy && item.itemId != android.R.id.selectAll) {
                    menu.removeItem(item.itemId)
                }
            }
        }

        override fun onActionItemClicked(
            mode: ActionMode,
            item: MenuItem,
        ): Boolean = contextAction(item.itemId)

        override fun onDestroyActionMode(mode: ActionMode) {
            if (actionMode === mode) actionMode = null
        }
    }
}

private class SelectionTextView(
    context: Context,
) : TextView(context) {
    var onRangeChanged: ((Int, Int) -> Unit)? = null
    var onContextAction: ((Int) -> Boolean)? = null
    var onTouchState: ((Boolean) -> Unit)? = null
    override fun onSelectionChanged(
        selStart: Int,
        selEnd: Int,
    ) {
        super.onSelectionChanged(selStart, selEnd)
        onRangeChanged?.invoke(selStart, selEnd)
    }

    override fun onTextContextMenuItem(id: Int): Boolean =
        if (onContextAction?.invoke(id) == true) true else super.onTextContextMenuItem(id)

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) onTouchState?.invoke(true)
        val handled = super.onTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
            onTouchState?.invoke(false)
        }
        return handled
    }
}

private data class Snapshot(
    val revision: Int,
    val text: String,
    val boxes: List<SelectionCell>,
    val regions: List<SelectionRegion>,
    val selection: Pair<Int, Int>?,
    val accent: Int,
    val selectionColor: Int,
    val showMenu: Boolean,
    val editable: Boolean,
) {
    companion object {
        fun parse(map: Map<*, *>): Snapshot {
            fun Map<*, *>.number(name: String): Double =
                (get(name) as? Number)?.toDouble() ?: throw IllegalArgumentException("Missing $name")
            val selection =
                (map["selection"] as? Map<*, *>)?.let {
                    it.number("base").toInt() to it.number("extent").toInt()
                }
            return Snapshot(
                revision = map.number("revision").toInt(),
                text = map["text"] as? String ?: throw IllegalArgumentException("Missing text"),
                boxes =
                    (map["boxes"] as? List<*>)?.map { raw ->
                        val box = raw as? Map<*, *> ?: throw IllegalArgumentException("Invalid box")
                        SelectionCell(
                            box.number("start").toInt(),
                            box.number("end").toInt(),
                            box.number("left"),
                            box.number("top"),
                            box.number("right"),
                            box.number("bottom"),
                            box["rtl"] == true,
                        )
                    } ?: throw IllegalArgumentException("Missing boxes"),
                regions =
                    (map["regions"] as? List<*>)?.map { raw ->
                        val region = raw as? Map<*, *> ?: throw IllegalArgumentException("Invalid region")
                        SelectionRegion(
                            region.number("start").toInt(),
                            region.number("end").toInt(),
                            region.number("left"),
                            region.number("top"),
                            region.number("right"),
                            region.number("bottom"),
                        )
                    } ?: emptyList(),
                selection = selection,
                accent = (map["accent"] as? Number)?.toInt() ?: Color.BLUE,
                selectionColor = (map["selectionColor"] as? Number)?.toInt() ?: Color.TRANSPARENT,
                showMenu = map["showMenu"] == true,
                editable = map["editable"] == true,
            )
        }
    }
}
