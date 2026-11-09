import UIKit

/// Supplies the system selection controls with geometry, without laying out or
/// redrawing the document. Flutter retains input focus and the action menu.
final class NativeSelectionView: UIView, UITextInput {
  var onEvent: ((String, [String: Any]) -> Void)?
  private var geometry = SelectionGeometry(text: "", boxes: [])
  private var revision = -1
  private var selection: NativeTextRange?
  private var suppressEvents = false
  private var adjusting = false
  private var showMenu = false
  private var highlightTint: UIColor?
  private var readyRevision: Int?
  private var controls: NativeSelectionControlsHost?
  private lazy var selectionTokenizer = NativeSelectionTokenizer(textInput: self)

  weak var inputDelegate: UITextInputDelegate?
  var tokenizer: UITextInputTokenizer { selectionTokenizer }
  var markedTextRange: UITextRange? { nil }
  var markedTextStyle: [NSAttributedString.Key: Any]?
  var selectionAffinity: UITextStorageDirection = .forward
  var beginningOfDocument: UITextPosition { NativeTextPosition(0) }
  var endOfDocument: UITextPosition { NativeTextPosition(geometry.length) }
  var textInputView: UIView { self }
  var hasText: Bool { geometry.length > 0 }
  var isEditable: Bool { false }

  // Flutter owns focus and input; this view only hosts selection controls.
  override var canBecomeFirstResponder: Bool { false }

  var selectedTextRange: UITextRange? {
    get { selection }
    set {
      guard let range = newValue as? NativeTextRange else {
        assignSelection(nil)
        return
      }
      assignSelection(
        NativeTextRange(
          base: geometry.snapped(range.base, forward: range.base > range.extent),
          extent: geometry.snapped(range.extent, forward: range.extent >= range.base)
        )
      )
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = false
    // Geometry is physical; per-cell writing direction handles text bidi.
    semanticContentAttribute = .forceLeftToRight
    // The Flutter text surface already supplies document semantics. Avoid
    // announcing the same text twice through the transparent native overlay.
    isAccessibilityElement = false
    if #available(iOS 17.0, *) { controls = NativeSelectionControls(view: self) }
  }

  required init?(coder: NSCoder) { nil }

  @discardableResult
  func update(_ snapshot: [String: Any]) -> Bool {
    guard let nextRevision = snapshot["revision"] as? Int,
      nextRevision >= revision,
      let text = snapshot["text"] as? String,
      let boxes = snapshot["boxes"] as? [[String: Any]]
    else { return false }
    guard snapshot["editable"] as? Bool != true else {
      onEvent?(
        "unsupportedGeometry",
        ["revision": nextRevision, "reason": "Editable surfaces require a native input bridge"]
      )
      return false
    }
    let nextGeometry = revision == nextRevision ? nil : SelectionGeometry(text: text, boxes: boxes)
    if let nextGeometry,
      nextGeometry.boxes.isEmpty || nextGeometry.boxes.count != boxes.count
    {
      onEvent?(
        "unsupportedGeometry",
        ["revision": nextRevision, "reason": "Missing or invalid text cell geometry"]
      )
      return false
    }
    suppressEvents = true
    defer { suppressEvents = false }
    readyRevision = nil
    if let nextGeometry {
      inputDelegate?.textWillChange(self)
      revision = nextRevision
      controls?.cancelDrag()
      geometry = nextGeometry
      inputDelegate?.textDidChange(self)
    }
    showMenu = snapshot["showMenu"] as? Bool ?? false
    if let accent = snapshot["accent"] as? NSNumber {
      tintColor = UIColor(argb: accent.uint32Value)
    }
    if let color = snapshot["selectionColor"] as? NSNumber {
      highlightTint = UIColor(argb: color.uint32Value)
    }
    if let range = snapshot["selection"] as? [String: Any],
      let base = range["base"] as? Int,
      let extent = range["extent"] as? Int
    {
      select(base: base, extent: extent, notify: false)
    } else {
      clear(notify: false)
    }
    return true
  }

  func select(base: Int, extent: Int, notify: Bool) {
    guard base >= 0, extent >= 0 else {
      clear(notify: notify)
      return
    }
    let wasSuppressed = suppressEvents
    suppressEvents = !notify || wasSuppressed
    assignSelection(
      NativeTextRange(
        base: geometry.snapped(base, forward: base > extent),
        extent: geometry.snapped(extent, forward: extent >= base)
      ),
      notifyInputDelegate: true
    )
    suppressEvents = wasSuppressed
  }

  func clear(notify: Bool) {
    let wasSuppressed = suppressEvents
    suppressEvents = !notify || wasSuppressed
    assignSelection(nil, notifyInputDelegate: true)
    setSelectionAdjusting(false)
    suppressEvents = wasSuppressed
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      clear(notify: false)
    } else {
      updateNativeDisplay()
    }
  }

  private func assignSelection(_ range: NativeTextRange?, notifyInputDelegate: Bool = false) {
    if range?.base == selection?.base, range?.extent == selection?.extent {
      updateNativeDisplay()
      return
    }
    // UIKit already knows about changes made through its UITextInput setter.
    if notifyInputDelegate { inputDelegate?.selectionWillChange(self) }
    selection = range
    if notifyInputDelegate { inputDelegate?.selectionDidChange(self) }
    updateNativeDisplay()
    guard !suppressEvents else { return }
    onEvent?(
      "selectionChanged",
      ["revision": revision, "base": range?.base ?? -1, "extent": range?.extent ?? -1]
    )
  }

  private func updateNativeDisplay() {
    let active = window != nil && selection?.isEmpty == false && !geometry.boxes.isEmpty
    let ready = controls?.update(active: active, accent: tintColor, highlight: highlightTint) == true
    if ready, readyRevision != revision {
      readyRevision = revision
      onEvent?("ready", ["revision": revision])
    }
    if !active { readyRevision = nil }
  }

  func selectionOffset(near point: CGPoint) -> Int? { geometry.nearest(to: point) }

  func selectionCaret(at offset: Int, isEnd: Bool) -> CGRect {
    geometry.caret(at: offset, preferPrevious: isEnd)
  }

  func setSelectionAdjusting(_ value: Bool) {
    guard adjusting != value else { return }
    adjusting = value
    onEvent?("adjusting", ["revision": revision, "value": value])
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    guard showMenu, selection?.isEmpty == false else { return false }
    return action == #selector(copy(_:)) || action == #selector(selectAll(_:))
  }

  override func copy(_ sender: Any?) {
    guard let selection, let text = text(in: selection), !text.isEmpty else { return }
    UIPasteboard.general.string = text
  }

  override func selectAll(_ sender: Any?) {
    select(base: 0, extent: geometry.length, notify: true)
  }

  @available(iOS 16.0, *)
  func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
    showMenu ? nil : UIMenu(children: [])
  }

  // The surface is intentionally read-only; document edits belong to its owner.
  func insertText(_ text: String) {}
  func deleteBackward() {}
  func replace(_ range: UITextRange, withText text: String) {}
  func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
  func unmarkText() {}
  func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}
  func shouldChangeText(in range: UITextRange, replacementText text: String) -> Bool { false }

  func text(in range: UITextRange) -> String? {
    guard let range = range as? NativeTextRange,
      range.lower >= 0, range.upper <= geometry.length
    else { return nil }
    return geometry.text.substring(with: NSRange(location: range.lower, length: range.upper - range.lower))
  }

  func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
    guard let from = fromPosition as? NativeTextPosition,
      let to = toPosition as? NativeTextPosition
    else { return nil }
    return NativeTextRange(base: from.offset, extent: to.offset)
  }

  func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
    guard let position = position as? NativeTextPosition else { return nil }
    let result = position.offset.addingReportingOverflow(offset)
    guard !result.overflow, result.partialValue >= 0, result.partialValue <= geometry.length else { return nil }
    return NativeTextPosition(geometry.snapped(result.partialValue, forward: offset > 0))
  }

  func position(
    from position: UITextPosition,
    in direction: UITextLayoutDirection,
    offset: Int
  ) -> UITextPosition? {
    guard let position = position as? NativeTextPosition else { return nil }
    switch direction {
    case .up, .down:
      let caret = geometry.caret(at: position.offset)
      let y = caret.midY + (direction == .up ? -1 : 1) * CGFloat(offset) * caret.height
      return geometry.nearest(to: CGPoint(x: caret.minX, y: y)).map(NativeTextPosition.init)
    case .left, .right:
      let rtl = geometry.box(at: position.offset)?.rtl ?? false
      let forwards = (direction == .right) != rtl
      return self.position(from: position, offset: forwards ? offset : -offset)
    @unknown default:
      return nil
    }
  }

  func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
    guard let position = position as? NativeTextPosition, let other = other as? NativeTextPosition
    else { return .orderedSame }
    if position.offset == other.offset { return .orderedSame }
    return position.offset < other.offset ? .orderedAscending : .orderedDescending
  }

  func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
    guard let from = from as? NativeTextPosition, let to = toPosition as? NativeTextPosition else { return 0 }
    return to.offset - from.offset
  }

  func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
    guard let range = range as? NativeTextRange else { return nil }
    // Match UITextView's range endpoints, including RTL text.
    let last = direction == .down || direction == .right
    return NativeTextPosition(last ? range.upper : range.lower)
  }

  func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
    guard let position = position as? NativeTextPosition else { return nil }
    // UITextView extends ranges in storage order; position movement is visual.
    let backwards = direction == .up || direction == .left
    return backwards
      ? NativeTextRange(base: geometry.previousBoundary(position.offset), extent: position.offset)
      : NativeTextRange(base: position.offset, extent: geometry.nextBoundary(position.offset))
  }

  func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
    guard let position = position as? NativeTextPosition else { return .natural }
    return geometry.box(at: position.offset, preferPrevious: direction == .backward)?.rtl == true
      ? .rightToLeft : .leftToRight
  }

  func firstRect(for range: UITextRange) -> CGRect {
    guard let range = range as? NativeTextRange else { return .zero }
    return geometry.selectionRects(start: range.lower, end: range.upper).first?.rect
      ?? caretRect(for: range.start)
  }

  func caretRect(for position: UITextPosition) -> CGRect {
    guard let position = position as? NativeTextPosition else { return .zero }
    let preferPrevious: Bool
    if let selection, !selection.isEmpty, position.offset == selection.upper {
      preferPrevious = true
    } else if let selection, !selection.isEmpty, position.offset == selection.lower {
      preferPrevious = false
    } else {
      preferPrevious = selectionAffinity == .backward
    }
    return geometry.caret(at: position.offset, preferPrevious: preferPrevious)
  }

  func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
    guard let range = range as? NativeTextRange else { return [] }
    return geometry.selectionRects(start: range.lower, end: range.upper)
  }

  func closestPosition(to point: CGPoint) -> UITextPosition? {
    geometry.nearest(to: point).map(NativeTextPosition.init)
  }

  func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
    guard let range = range as? NativeTextRange else { return nil }
    return geometry.nearest(to: point, within: range.lower..<range.upper).map(NativeTextPosition.init)
  }

  func characterRange(at point: CGPoint) -> UITextRange? {
    guard let box = geometry.character(at: point) else { return nil }
    return NativeTextRange(base: geometry.snapped(box.start), extent: geometry.snapped(box.end, forward: true))
  }

  func lineRange(containing position: NativeTextPosition) -> NativeTextRange? {
    guard let line = geometry.line(containing: position.offset) else { return nil }
    return NativeTextRange(base: line.lowerBound, extent: line.upperBound)
  }
}

private final class NativeSelectionTokenizer: UITextInputStringTokenizer {
  private weak var selectionView: NativeSelectionView?

  init(textInput: NativeSelectionView) {
    selectionView = textInput
    super.init(textInput: textInput)
  }

  override func rangeEnclosingPosition(
    _ position: UITextPosition,
    with granularity: UITextGranularity,
    inDirection direction: UITextDirection
  ) -> UITextRange? {
    let direction = storageDirection(direction, at: position)
    guard granularity == .line, let position = position as? NativeTextPosition else {
      return super.rangeEnclosingPosition(position, with: granularity, inDirection: direction)
    }
    guard let line = selectionView?.lineRange(containing: position) else { return nil }
    let inside = isForward(direction)
      ? position.offset >= line.lower && position.offset < line.upper
      : position.offset > line.lower && position.offset <= line.upper
    return inside ? line : nil
  }

  override func isPosition(
    _ position: UITextPosition,
    atBoundary granularity: UITextGranularity,
    inDirection direction: UITextDirection
  ) -> Bool {
    let direction = storageDirection(direction, at: position)
    guard granularity == .line, let position = position as? NativeTextPosition,
      let line = selectionView?.lineRange(containing: position)
    else { return super.isPosition(position, atBoundary: granularity, inDirection: direction) }
    return position.offset == (isForward(direction) ? line.upper : line.lower)
  }

  override func position(
    from position: UITextPosition,
    toBoundary granularity: UITextGranularity,
    inDirection direction: UITextDirection
  ) -> UITextPosition? {
    let direction = storageDirection(direction, at: position)
    guard granularity == .line, let position = position as? NativeTextPosition,
      let line = selectionView?.lineRange(containing: position)
    else { return super.position(from: position, toBoundary: granularity, inDirection: direction) }
    return NativeTextPosition(isForward(direction) ? line.upper : line.lower)
  }

  override func isPosition(
    _ position: UITextPosition,
    withinTextUnit granularity: UITextGranularity,
    inDirection direction: UITextDirection
  ) -> Bool {
    let direction = storageDirection(direction, at: position)
    guard granularity == .line, let position = position as? NativeTextPosition,
      let line = selectionView?.lineRange(containing: position)
    else { return super.isPosition(position, withinTextUnit: granularity, inDirection: direction) }
    return isForward(direction)
      ? position.offset >= line.lower && position.offset < line.upper
      : position.offset > line.lower && position.offset <= line.upper
  }

  private func isForward(_ direction: UITextDirection) -> Bool {
    direction.rawValue == UITextStorageDirection.forward.rawValue
  }

  private func storageDirection(_ direction: UITextDirection, at position: UITextPosition) -> UITextDirection {
    let raw = direction.rawValue
    if raw == UITextLayoutDirection.left.rawValue || raw == UITextLayoutDirection.right.rawValue {
      let rtl = selectionView?.baseWritingDirection(for: position, in: .forward) == .rightToLeft
      let forward = (raw == UITextLayoutDirection.left.rawValue) == rtl
      return UITextDirection(rawValue: forward ? UITextStorageDirection.forward.rawValue : UITextStorageDirection.backward.rawValue)
    }
    if raw == UITextLayoutDirection.up.rawValue {
      return UITextDirection(rawValue: UITextStorageDirection.backward.rawValue)
    }
    if raw == UITextLayoutDirection.down.rawValue {
      return UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)
    }
    return direction
  }
}

private extension UIColor {
  convenience init(argb: UInt32) {
    self.init(
      red: CGFloat((argb >> 16) & 0xff) / 255,
      green: CGFloat((argb >> 8) & 0xff) / 255,
      blue: CGFloat(argb & 0xff) / 255,
      alpha: CGFloat((argb >> 24) & 0xff) / 255
    )
  }
}
