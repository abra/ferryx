import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  /// The app's top row (`AppMetrics.topBarHeight` for macOS) and where the
  /// traffic lights start in it; `WindowFrame.trafficLightsInset` in Dart
  /// keeps the first control clear of them by these numbers.
  private static let topRowHeight: CGFloat = 52
  private static let buttonsLeading: CGFloat = 20

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // AppKit lays the title bar out again on these and puts the buttons
    // back in its 28 pt strip; each one puts them back in the top row.
    let names: [NSNotification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
      NSWindow.didChangeBackingPropertiesNotification,
    ]
    for name in names {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowButtonsMoved), name: name, object: self)
    }
  }

  // A new title (every page the app opens) relayouts the title bar too.
  override var title: String {
    didSet { placeWindowButtons() }
  }

  // The window stays hidden until Dart has read the remembered frame and
  // calls `show()` (window_state.dart); otherwise it would first appear at
  // the default size and jump, and `showWindow` would skip the restore
  // because the window was already visible.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
    placeWindowButtons()
  }

  @objc private func windowButtonsMoved(_ notification: Notification) {
    placeWindowButtons()
  }

  /// Centres the traffic lights in the app's top row, as a unified toolbar
  /// does, while the system title bar is hidden (window_manager's hidden
  /// style adds `fullSizeContentView`). Full screen keeps AppKit's own
  /// title bar.
  private func placeWindowButtons() {
    guard styleMask.contains(.fullSizeContentView),
      !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let miniaturize = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let container = close.superview?.superview
    else { return }
    let height = Self.topRowHeight
    var frame = container.frame
    let top = self.frame.height - height
    if frame.height != height || frame.origin.y != top {
      frame.size.height = height
      frame.origin.y = top
      container.frame = frame
    }
    let spacing = miniaturize.frame.minX - close.frame.maxX
    let y = ((height - close.frame.height) / 2).rounded()
    var x = Self.buttonsLeading
    for button in [close, miniaturize, zoom] {
      if button.frame.origin != NSPoint(x: x, y: y) {
        button.setFrameOrigin(NSPoint(x: x, y: y))
      }
      x += button.frame.width + spacing
    }
  }
}
