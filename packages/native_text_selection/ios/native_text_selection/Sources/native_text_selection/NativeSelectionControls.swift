import UIKit

@MainActor
protocol NativeSelectionControlsHost: AnyObject {
  func update(active: Bool, accent: UIColor, highlight: UIColor?) -> Bool
  func cancelDrag()
}

/// UIKit draws the controls and loupe. The drag keeps its source anchor while
/// mapping physical coordinates through the document's existing text geometry.
@available(iOS 17.0, *)
@MainActor
final class NativeSelectionControls: NSObject, NativeSelectionControlsHost,
  UITextSelectionDisplayInteractionDelegate, UIGestureRecognizerDelegate
{
  private struct Drag {
    let anchor: Int
    let moving: Int
    let grip: CGPoint
  }

  private weak var view: NativeSelectionView?
  private var display: UITextSelectionDisplayInteraction?
  private let pan = UIPanGestureRecognizer()
  private var candidate: Drag?
  private var drag: Drag?
  private var loupe: UITextLoupeSession?
  private var active = false

  init(view: NativeSelectionView) {
    self.view = view
    super.init()
    let display = UITextSelectionDisplayInteraction(textInput: view, delegate: self)
    self.display = display
    view.addInteraction(display)
    pan.maximumNumberOfTouches = 1
    pan.delegate = self
    pan.addTarget(self, action: #selector(didPan(_:)))
    view.addGestureRecognizer(pan)
  }

  func update(active: Bool, accent: UIColor, highlight: UIColor?) -> Bool {
    guard let display else { return false }
    self.active = active
    if !active { finish() }
    pan.isEnabled = active
    if display.isActivated != active { display.isActivated = active }
    display.setNeedsSelectionUpdate()
    display.layoutManagedSubviews()
    if let highlight { display.highlightView.tintColor = highlight }
    for handle in display.handleViews { handle.tintColor = accent }
    return active && display.handleViews.count == 2
  }

  func cancelDrag() {
    finish()
    pan.isEnabled = false
    pan.isEnabled = active
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard active, let view, let range = view.selectedTextRange as? NativeTextRange,
      !range.isEmpty
    else { return false }
    let point = touch.location(in: view)
    let start = view.selectionCaret(at: range.lower, isEnd: false)
    let end = view.selectionCaret(at: range.upper, isEnd: true)
    let startHit = hitRect(for: start).contains(point)
    let endHit = hitRect(for: end).contains(point)
    guard startHit || endHit else { return false }
    let movingEnd = endHit && (!startHit || distance(point, end) <= distance(point, start))
    let caret = movingEnd ? end : start
    candidate = Drag(
      anchor: movingEnd ? range.lower : range.upper,
      moving: movingEnd ? range.upper : range.lower,
      grip: CGPoint(x: point.x - caret.midX, y: point.y - caret.midY)
    )
    return true
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    active && candidate != nil
  }

  @objc private func didPan(_ recognizer: UIPanGestureRecognizer) {
    guard let view else { return }
    switch recognizer.state {
    case .began:
      drag = candidate
      guard let drag else { return }
      view.setSelectionAdjusting(true)
      let caret = view.selectionCaret(at: drag.moving, isEnd: drag.moving > drag.anchor)
      loupe = UITextLoupeSession.begin(
        at: CGPoint(x: caret.midX, y: caret.midY),
        fromSelectionWidgetView: nil,
        in: view
      )
      move(recognizer.location(in: view))
    case .changed:
      move(recognizer.location(in: view))
    case .ended:
      move(recognizer.location(in: view))
      finish()
    case .cancelled, .failed:
      finish()
    default:
      break
    }
  }

  private func move(_ point: CGPoint) {
    guard let view, let drag else { return }
    let target = CGPoint(x: point.x - drag.grip.x, y: point.y - drag.grip.y)
    guard let offset = view.selectionOffset(near: target) else { return }
    // A transient collapsed range must not dispose the active surface while
    // the moving handle crosses its fixed source anchor.
    if offset != drag.anchor { view.select(base: drag.anchor, extent: offset, notify: true) }
    let caret = view.selectionCaret(at: offset, isEnd: offset > drag.anchor)
    loupe?.move(to: target, withCaretRect: caret, trackingCaret: true)
  }

  private func finish() {
    loupe?.invalidate()
    loupe = nil
    drag = nil
    candidate = nil
    view?.setSelectionAdjusting(false)
  }

  private func hitRect(for caret: CGRect) -> CGRect {
    CGRect(x: caret.midX - 24, y: caret.minY - 24, width: 48, height: caret.height + 48)
  }

  private func distance(_ point: CGPoint, _ caret: CGRect) -> CGFloat {
    let dx = point.x - caret.midX
    let dy = max(caret.minY - point.y, point.y - caret.maxY, 0)
    return hypot(dx, dy)
  }
}
