import XCTest
import UIKit

final class HarnessUITests: XCTestCase {
  func testNativeHandleDrag() {
    let app = XCUIApplication()
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "0:6")
    let before = XCTAttachment(screenshot: app.screenshot())
    before.name = "Native-selection-before"
    before.lifetime = .keepAlways
    add(before)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let end = origin.withOffset(CGVector(dx: 130, dy: 198))
    let target = origin.withOffset(CGVector(dx: 260, dy: 198))
    end.press(forDuration: 0.25, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "0:15")
    XCTAssertEqual(app.staticTexts["drag-events"].label, "finished")
    XCTAssertFalse(app.menuItems["Copy"].exists)
    XCTAssertFalse(app.buttons["Copy"].exists)
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "Native-selection-after"
    after.lifetime = .keepAlways
    add(after)
    app.buttons["preview"].tap()
    let preview = XCTAttachment(screenshot: app.screenshot())
    preview.name = "Native-selection-preview"
    preview.lifetime = .keepAlways
    add(preview)
    XCTAssertFalse(app.keyboards.firstMatch.exists)
  }

  func testNativeCrossingKeepsTheOppositeSourceEndpoint() {
    let app = XCUIApplication()
    app.launchArguments = ["--middle"]
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "7:16")
    let origin = app.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 145.5, dy: 176))
      .press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: 340.5, dy: 176)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "16:20")
    XCTAssertEqual(app.staticTexts["selected-text"].label, " tex")
    XCTAssertEqual(app.staticTexts["drag-events"].label, "finished")
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Native-selection-crossed"
    image.lifetime = .keepAlways
    add(image)
  }

  func testNativeWordCellsStayAtomic() {
    let app = XCUIApplication()
    app.launchArguments = ["--atomic"]
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "0:6")
    let origin = app.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 130, dy: 198))
      .press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: 250, dy: 198)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "0:16")
    XCTAssertEqual(app.staticTexts["selected-text"].label, "Native selection")
    XCTAssertEqual(app.staticTexts["drag-events"].label, "finished")
  }

  func testNativeArabicRTLHandleDrag() {
    let app = XCUIApplication()
    app.launchArguments = ["--rtl"]
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "0:5")
    XCTAssertEqual(app.staticTexts["selected-text"].label, "مرحبا")
    let edges = app.staticTexts["edges"].label.split(separator: ";").map {
      $0.split(separator: ",").map { Double($0)! }
    }
    XCTAssertLessThan(edges[1][0], edges[0][0])
    let before = XCTAttachment(screenshot: app.screenshot())
    before.name = "Native-selection-phone-rtl-before"
    before.lifetime = .keepAlways
    add(before)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let end = origin.withOffset(CGVector(dx: edges[0][0], dy: edges[0][1]))
    let target = origin.withOffset(CGVector(dx: edges[1][0], dy: edges[1][1]))
    end.press(forDuration: 0.25, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "0:13")
    XCTAssertEqual(app.staticTexts["selected-text"].label, "مرحبا بالعالم")
    XCTAssertEqual(app.staticTexts["drag-events"].label, "finished")
    XCTAssertFalse(app.buttons["Copy"].exists)
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "Native-selection-phone-rtl-after"
    after.lifetime = .keepAlways
    add(after)
  }

  func testReferenceArabicRTLHandleDrag() {
    let app = XCUIApplication()
    app.launchArguments = ["--rtl", "--reference"]
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "0:5")
    let edges = app.staticTexts["edges"].label.split(separator: ";").map {
      $0.split(separator: ",").map { Double($0)! }
    }
    let before = XCTAttachment(screenshot: app.screenshot())
    before.name = "Reference-phone-rtl-before"
    before.lifetime = .keepAlways
    add(before)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: edges[0][0], dy: edges[0][1]))
      .press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: edges[1][0], dy: edges[1][1])), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "0:13")
    XCTAssertEqual(app.staticTexts["selected-text"].label, "مرحبا بالعالم")
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "Reference-phone-rtl-after"
    after.lifetime = .keepAlways
    add(after)
  }

  func testArabicSelectionCanEndInsideTheEnglishRun() {
    let app = XCUIApplication()
    app.launchArguments = ["--rtl"]
    app.launch()
    let range = app.staticTexts["range"]
    XCTAssertTrue(range.waitForExistence(timeout: 10))
    XCTAssertEqual(range.label, "0:5")
    let edges = app.staticTexts["edges"].label.split(separator: ";").map {
      $0.split(separator: ",").map { Double($0)! }
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = .rightToLeft
    paragraph.alignment = .right
    let reference = UITextView(frame: CGRect(x: 0, y: 0, width: app.frame.width - 48, height: 240))
    reference.textContainerInset = .zero
    reference.textContainer.lineFragmentPadding = 0
    reference.attributedText = NSAttributedString(string: "مرحبا بالعالم — Flutter 123\nالقراءة باللغة العربية", attributes: [
      .font: UIFont.systemFont(ofSize: 26), .paragraphStyle: paragraph
    ])
    reference.layoutIfNeeded()
    let start = reference.position(from: reference.beginningOfDocument, offset: 22)!
    let end = reference.position(from: start, offset: 1)!
    let targetRange = reference.textRange(from: start, to: end)!
    let targetRect = reference.selectionRects(for: targetRange).filter { !$0.rect.isEmpty }
      .reduce(CGRect.null) { $0.union($1.rect) }.offsetBy(dx: 24, dy: 160)
    XCTAssertLessThan(targetRect.width, 20)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: edges[0][0], dy: edges[0][1]))
      .press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: targetRect.maxX - 0.25, dy: targetRect.midY)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertEqual(range.label, "0:23")
    XCTAssertEqual(app.staticTexts["selected-text"].label, "مرحبا بالعالم — Flutter")
    XCTAssertEqual(app.staticTexts["drag-events"].label, "finished")
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Native-selection-phone-rtl-to-English"
    image.lifetime = .keepAlways
    add(image)
  }
}
