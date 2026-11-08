import Cocoa
import XCTest
@testable import Ferryx

@MainActor
class RunnerTests: XCTestCase {
  func testMonospaceFontCatalogContainsFamiliesWithoutProportionalFaces() {
    let families = NativeServices.monospaceFontFamilies()
    XCTAssertTrue(families.contains("Menlo"))
    XCTAssertFalse(families.contains("Helvetica"))
    XCTAssertFalse(families.contains(where: { $0.isEmpty || $0.hasPrefix(".") }))
    XCTAssertEqual(Set(families).count, families.count)
  }

  func testTrafficLightsStayInsideTheToolbarAfterAppearanceTitleAndSizeChanges() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    defer { window.close() }

    for size in [NSSize(width: 1000, height: 700), NSSize(width: 800, height: 500)] {
      window.setContentSize(size)
      window.layoutIfNeeded()
      // The app changes the title as the current folder changes.
      window.title = "Ferryx \(size.width)"
      window.layoutIfNeeded()
      try assertTrafficLights(in: window)
      // window_manager applies these appearances after Flutter builds its theme.
      // AppKit relayouts the title bar even when the window size stays unchanged.
      for appearance in [NSAppearance.Name.vibrantLight, .vibrantDark, .vibrantLight] {
        window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        window.layoutIfNeeded()
        try assertTrafficLights(in: window)
      }
    }
  }

  private func assertTrafficLights(in window: NSWindow) throws {
    let content = try XCTUnwrap(window.contentView)
    let contentInWindow = content.convert(content.bounds, to: nil)
    var previous: NSRect?
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      let button = try XCTUnwrap(window.standardWindowButton(kind))
      let rect = button.convert(button.bounds, to: nil)
      XCTAssertEqual(contentInWindow.maxY - rect.midY, 26, accuracy: 0.5)
      XCTAssertTrue(contentInWindow.contains(rect), "The whole button must be inside the window")
      // A correct window position is not enough if a title-bar ancestor clips it.
      var ancestor = button.superview
      while let view = ancestor {
        let bounds = view.convert(view.bounds, to: nil)
        XCTAssertTrue(bounds.contains(rect), "\(type(of: view)) clips \(kind)")
        ancestor = view.superview
      }
      if let previous = previous {
        XCTAssertEqual(rect.minX - previous.maxX, 6, accuracy: 0.5)
      } else {
        XCTAssertEqual(rect.minX - contentInWindow.minX, 20, accuracy: 0.5)
      }
      previous = rect
    }
  }
}
