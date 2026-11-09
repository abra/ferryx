import UIKit
import XCTest
@testable import native_text_selection

final class SelectionGeometryTests: XCTestCase {
  func testTextPositionsHaveValueEquality() {
    let position = NativeTextPosition(5)
    let equivalent = NativeTextPosition(5)
    XCTAssertTrue(position.isEqual(equivalent))
    XCTAssertEqual(position.hash, equivalent.hash)
    XCTAssertFalse(position.isEqual(NativeTextPosition(6)))
    let range = NativeTextRange(base: 0, extent: 5)
    XCTAssertTrue(range.start.isEqual(range.start))
    XCTAssertTrue(range.end.isEqual(position))
  }

  func testUTF16PositionsRespectExtendedGraphemes() {
    let geometry = SelectionGeometry(text: "A👨‍👩‍👧‍👦e\u{301}B", boxes: [])
    XCTAssertEqual(geometry.boundaries, [0, 1, 12, 14, 15])
    XCTAssertEqual(geometry.snapped(5), 1)
    XCTAssertEqual(geometry.snapped(5, forward: true), 12)
    XCTAssertEqual(geometry.previousBoundary(12), 1)
    XCTAssertEqual(geometry.nextBoundary(12), 14)
    XCTAssertEqual(geometry.snapped(-1), 0)
    XCTAssertEqual(geometry.snapped(500), 15)
  }

  func testRTLInsertionEdgesAndSelectionMetadata() {
    let geometry = SelectionGeometry(
      text: "اب",
      boxes: [box(0, 1, 20, 20, 30, 40, rtl: true), box(1, 2, 10, 20, 20, 40, rtl: true)]
    )
    XCTAssertEqual(geometry.caret(at: 0).minX, 30)
    XCTAssertEqual(geometry.caret(at: 2).minX, 10)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 29, y: 30)), 0)
    let rects = geometry.selectionRects(start: 0, end: 2)
    XCTAssertEqual(rects.count, 1)
    XCTAssertEqual(rects[0].writingDirection, .rightToLeft)
    XCTAssertTrue(rects[0].containsStart)
    XCTAssertTrue(rects[0].containsEnd)
  }

  func testWrappingPreservesBothCaretAffinities() {
    let geometry = SelectionGeometry(
      text: "abcd",
      boxes: [
        box(0, 1, 10, 20, 20, 40), box(1, 2, 20, 20, 30, 40),
        box(2, 3, 10, 50, 20, 70), box(3, 4, 20, 50, 30, 70),
      ]
    )
    XCTAssertEqual(geometry.selectionRects(start: 0, end: 4).count, 2)
    XCTAssertEqual(geometry.caret(at: 2).minY, 50)
    XCTAssertEqual(geometry.caret(at: 2, preferPrevious: true).minY, 20)
    XCTAssertEqual(geometry.line(containing: 3), 2..<4)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 100, y: 60)), 4)
  }

  func testWordGeometryRemainsAtomic() {
    let geometry = SelectionGeometry(text: "word", boxes: [box(0, 4, 10, 20, 50, 40)])
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 11, y: 30)), 0)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 49, y: 30)), 4)
    XCTAssertEqual(geometry.selectionRects(start: 0, end: 4).first?.rect, CGRect(x: 10, y: 20, width: 40, height: 20))
  }

  func testInvalidNativeGeometryIsDiscarded() {
    let geometry = SelectionGeometry(
      text: "ab",
      boxes: [
        box(-1, 1, 10, 20, 20, 40), box(0, 5, 10, 20, 20, 40),
        box(0, 1, 30, 20, 10, 40), box(0, 1, 10, 40, 20, 20),
        box(1, 2, 20, 20, 30, 40),
      ]
    )
    XCTAssertEqual(geometry.boxes.count, 1)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 20, y: 30)), 1)
  }

  func testHitTestingInsideTrailingHalfKeepsTheTouchedCharacter() {
    let geometry = SelectionGeometry(
      text: "ab",
      boxes: [box(0, 1, 10, 20, 20, 40), box(1, 2, 20, 20, 30, 40)]
    )
    XCTAssertEqual(geometry.character(at: CGPoint(x: 19, y: 30))?.start, 0)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 19, y: 30)), 1)
  }

  func testMissingWhitespaceGeometryStillHasBothSelectionHandles() {
    let geometry = SelectionGeometry(
      text: " a ", boxes: [box(1, 2, 10, 20, 20, 40)]
    )
    let rects = geometry.selectionRects(start: 0, end: 3)
    XCTAssertEqual(rects.count, 1)
    XCTAssertTrue(rects[0].containsStart)
    XCTAssertTrue(rects[0].containsEnd)
  }

  func testLineGranularityDoesNotJoinSeparateColumnsAtTheSameHeight() {
    let geometry = SelectionGeometry(
      text: "abcd",
      boxes: [
        box(0, 1, 10, 20, 20, 40), box(1, 2, 10, 50, 20, 70),
        box(2, 3, 100, 20, 110, 40), box(3, 4, 100, 50, 110, 70),
      ]
    )
    XCTAssertEqual(geometry.line(containing: 0), 0..<1)
    XCTAssertEqual(geometry.line(containing: 2), 2..<3)
    XCTAssertEqual(geometry.nearest(to: CGPoint(x: 109, y: 30)), 3)
  }

  private func box(
    _ start: Int, _ end: Int,
    _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
    rtl: Bool = false
  ) -> [String: Any] {
    ["start": start, "end": end, "left": left, "top": top, "right": right, "bottom": bottom, "rtl": rtl]
  }
}

final class NativeSelectionViewTests: XCTestCase {
  func testProgrammaticSelectionDoesNotEchoButUIKitChangesDo() {
    let view = NativeSelectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    var events: [String] = []
    view.onEvent = { name, _ in events.append(name) }
    XCTAssertTrue(view.update(snapshot(revision: 1)))
    XCTAssertEqual(view.text(in: view.selectedTextRange!), "ab")
    XCTAssertTrue(events.isEmpty)
    view.selectedTextRange = NativeTextRange(base: 1, extent: 3)
    XCTAssertEqual(events, ["selectionChanged"])
    XCTAssertEqual(view.text(in: view.selectedTextRange!), "bc")
    view.clear(notify: false)
    XCTAssertNil(view.selectedTextRange)
    XCTAssertEqual(events.count, 1)
  }

  func testOlderRevisionCannotReplaceTextOrSelection() {
    let view = NativeSelectionView(frame: .zero)
    XCTAssertTrue(view.update(snapshot(revision: 2)))
    var stale = snapshot(revision: 1)
    stale["text"] = "old"
    XCTAssertFalse(view.update(stale))
    XCTAssertEqual(view.text(in: view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)!), "abcd")
  }

  func testUIKitSelectionDoesNotEchoToInputDelegate() {
    let view = NativeSelectionView(frame: .zero)
    view.update(snapshot(revision: 1))
    let delegate = InputDelegateSpy()
    view.inputDelegate = delegate
    view.selectedTextRange = NativeTextRange(base: 1, extent: 3)
    XCTAssertTrue(delegate.selectionNotifications.isEmpty)
    view.select(base: 0, extent: 2, notify: false)
    XCTAssertEqual(delegate.selectionNotifications, ["will", "did"])
    view.clear(notify: false)
    XCTAssertEqual(delegate.selectionNotifications, ["will", "did", "will", "did"])
  }

  func testSurfaceIsReadOnlyAndOwnsUIKitInteraction() {
    let view = NativeSelectionView(frame: .zero)
    view.update(snapshot(revision: 1))
    view.insertText("replacement")
    view.deleteBackward()
    view.replace(view.selectedTextRange!, withText: "replacement")
    XCTAssertEqual(view.text(in: view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)!), "abcd")
    if #available(iOS 17.0, *) {
      XCTAssertTrue(view.interactions.contains { $0 is UITextSelectionDisplayInteraction })
    }
    XCTAssertFalse(view.canBecomeFirstResponder)
    XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
  }

  func testEditableSurfaceIsRejectedWithoutStealingKeyboardFocus() {
    let view = NativeSelectionView(frame: .zero)
    var unsupported: [String: Any]?
    view.onEvent = { name, arguments in
      if name == "unsupportedGeometry" { unsupported = arguments }
    }
    var editable = snapshot(revision: 1)
    editable["editable"] = true
    XCTAssertFalse(view.update(editable))
    XCTAssertEqual(unsupported?["revision"] as? Int, 1)
    XCTAssertFalse(view.isFirstResponder)
    XCTAssertNil(view.selectedTextRange)
  }

  func testInvalidGeometryCannotBecomeReadyOrReplaceAnAcceptedDocument() {
    let view = NativeSelectionView(frame: .zero)
    XCTAssertTrue(view.update(snapshot(revision: 1)))
    var events: [String] = []
    view.onEvent = { name, _ in events.append(name) }
    var invalid = snapshot(revision: 2)
    invalid["text"] = "replacement"
    invalid["boxes"] = [] as [[String: Any]]
    XCTAssertFalse(view.update(invalid))
    XCTAssertEqual(events, ["unsupportedGeometry"])
    XCTAssertEqual(view.text(in: view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)!), "abcd")
  }

  func testRTLRangeEndpointsAndCaretAffinityMatchUITextView() {
    let view = NativeSelectionView(frame: .zero)
    let parent = UIView()
    parent.semanticContentAttribute = .forceRightToLeft
    parent.addSubview(view)
    XCTAssertEqual(view.effectiveUserInterfaceLayoutDirection, .leftToRight)
    XCTAssertTrue(view.update([
      "revision": 1, "text": "اب ", "selection": ["base": 0, "extent": 2],
      "boxes": [
        ["start": 0, "end": 1, "left": 20.0, "top": 0.0, "right": 30.0, "bottom": 20.0, "rtl": true],
        ["start": 1, "end": 2, "left": 10.0, "top": 0.0, "right": 20.0, "bottom": 20.0, "rtl": true],
        ["start": 2, "end": 3, "left": 10.0, "top": 0.0, "right": 30.0, "bottom": 20.0, "rtl": true],
      ]
    ]))
    let range = view.selectedTextRange!
    XCTAssertEqual(view.caretRect(for: range.start).minX, 30)
    XCTAssertEqual(view.caretRect(for: range.end).minX, 10)
    let left = view.position(within: range, farthestIn: .left)!
    let right = view.position(within: range, farthestIn: .right)!
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: left), 0)
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: right), 2)
    XCTAssertEqual(view.firstRect(for: view.textRange(from: range.end, to: range.end)!).minX, 10)
    let middle = view.position(from: view.beginningOfDocument, offset: 1)!
    let previous = view.characterRange(byExtending: middle, in: .left)!
    let next = view.characterRange(byExtending: middle, in: .right)!
    XCTAssertEqual(view.text(in: previous), "ا")
    XCTAssertEqual(view.text(in: next), "ب")
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.position(from: middle, in: .left, offset: 1)!), 2)
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.position(from: middle, in: .right, offset: 1)!), 0)
    let visualLeft = UITextDirection(rawValue: UITextLayoutDirection.left.rawValue)
    let visualRight = UITextDirection(rawValue: UITextLayoutDirection.right.rawValue)
    let lineEnd = view.tokenizer.position(from: view.beginningOfDocument, toBoundary: .line, inDirection: visualLeft)!
    let lineStart = view.tokenizer.position(from: middle, toBoundary: .line, inDirection: visualRight)!
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: lineEnd), 3)
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: lineStart), 0)
    let wordEnd = view.tokenizer.position(from: view.beginningOfDocument, toBoundary: .word, inDirection: visualLeft)!
    XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: wordEnd), 2)
    XCTAssertNil(view.tokenizer.rangeEnclosingPosition(view.beginningOfDocument, with: .line, inDirection: visualRight))
    XCTAssertNotNil(view.tokenizer.rangeEnclosingPosition(view.beginningOfDocument, with: .line, inDirection: visualLeft))
  }

  func testReadyFollowsNativeDisplayActivationAndReplaysAfterUpdate() {
    guard #available(iOS 17.0, *) else { return }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let controller = UIViewController()
    let view = NativeSelectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    controller.view.addSubview(view)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      view.clear(notify: false)
      window.isHidden = true
    }
    var ready = 0
    view.onEvent = { name, _ in if name == "ready" { ready += 1 } }
    XCTAssertTrue(view.update(snapshot(revision: 1)))
    let display = view.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first
    XCTAssertEqual(display?.isActivated, true)
    XCTAssertEqual(display?.handleViews.count, 2)
    XCTAssertEqual(ready, 1)
    XCTAssertTrue(view.update(snapshot(revision: 1)))
    XCTAssertEqual(ready, 2)
    var preview = snapshot(revision: 2)
    preview["accent"] = UInt32(0xff0000ff)
    preview["selectionColor"] = UInt32(0x55ff0000)
    XCTAssertTrue(view.update(preview))
    XCTAssertEqual(display?.highlightView.tintColor, UIColor.red.withAlphaComponent(1.0 / 3.0))
    XCTAssertTrue(display?.handleViews.allSatisfy { $0.tintColor == UIColor.blue } == true)
    view.clear(notify: false)
    XCTAssertEqual(display?.isActivated, false)
  }

  private func snapshot(revision: Int) -> [String: Any] {
    [
      "revision": revision,
      "text": "abcd",
      "boxes": (0..<4).map { index in
        ["start": index, "end": index + 1, "left": Double(index * 10), "top": 0.0, "right": Double(index * 10 + 10), "bottom": 20.0]
      },
      "selection": ["base": 0, "extent": 2],
    ]
  }
}

private final class InputDelegateSpy: NSObject, UITextInputDelegate {
  var selectionNotifications: [String] = []
  func selectionWillChange(_ textInput: UITextInput?) { selectionNotifications.append("will") }
  func selectionDidChange(_ textInput: UITextInput?) { selectionNotifications.append("did") }
  func textWillChange(_ textInput: UITextInput?) {}
  func textDidChange(_ textInput: UITextInput?) {}
  @available(iOS 18.4, *)
  func conversationContext(_ context: UIConversationContext?, didChange textInput: UITextInput?) {}
}
