import Carbon
import Cocoa
import FlutterMacOS
import Quartz

/// Quick Look, the share picker, keyboard layout and font catalog for Dart
/// (`ChannelPlatformServices` in packages/platform_services) over the
/// `ferryx/platform` channel.
///
/// Quick Look: the panel is ordered front without taking the keys, so the
/// panel's cursor in Flutter keeps moving it (Dart sends `quickLook.select`
/// on every move); when the user clicks the panel and it takes the keys,
/// ↑ and ↓ go back to Dart as `quickLook.step`, and Space, Esc and ⌘Y
/// close it, as in Finder. `MainFlutterWindow` is the panel's controller in
/// the responder chain and hands the panel to [begin] and [end].
final class NativeServices: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private let channel: FlutterMethodChannel
  private weak var view: NSView?
  private var items: [URL] = []
  private var index = 0
  /// The panel is ours: opened for Dart and not yet closed.
  private var showing = false
  private var picker: NSSharingServicePicker?

  init(messenger: FlutterBinaryMessenger, view: NSView) {
    channel = FlutterMethodChannel(name: "ferryx/platform", binaryMessenger: messenger)
    self.view = view
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    // The layout changes with the menu, a key, or the window it was last
    // used in ("Automatically switch to a document's input source").
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(keyboardChanged),
      name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil, suspensionBehavior: .deliverImmediately)
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardChanged),
      name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  /// Whether the current layout types Latin letters (ASCII-capable): on
  /// another script Dart finds chords by the keys' places.
  private static func latinKeyboard() -> Bool {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
    else { return true }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
  }

  @objc private func keyboardChanged() {
    channel.invokeMethod("keyboard.changed", arguments: ["latin": Self.latinKeyboard()])
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "quickLook.show":
      let paths = arguments["paths"] as? [String] ?? []
      items = paths.map { URL(fileURLWithPath: $0) }
      index = clamped(arguments["index"] as? Int ?? 0)
      showQuickLook()
      result(nil)
    case "quickLook.select":
      index = clamped(arguments["index"] as? Int ?? 0)
      if showing, let panel = QLPreviewPanel.shared(), panel.isVisible {
        panel.currentPreviewItemIndex = index
      }
      result(nil)
    case "quickLook.close":
      closeQuickLook()
      result(nil)
    case "keyboard.latin":
      result(Self.latinKeyboard())
    case "fonts.monospaceFamilies":
      result(Self.monospaceFontFamilies())
    case "share":
      let paths = arguments["paths"] as? [String] ?? []
      let rect = arguments["rect"] as? [Double] ?? [0, 0, 0, 0]
      share(paths: paths, rect: rect)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func clamped(_ value: Int) -> Int {
    items.isEmpty ? 0 : min(max(value, 0), items.count - 1)
  }

  /// Families, not PostScript face names: Flutter chooses the weight itself.
  static func monospaceFontFamilies() -> [String] {
    let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
    let families = names.compactMap { NSFont(name: $0, size: 12)?.familyName }
      .filter { !$0.isEmpty && !$0.hasPrefix(".") }
    return Array(Set(families))
  }

  // MARK: - Quick Look

  private func showQuickLook() {
    guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return }
    showing = true
    if panel.isVisible && panel.dataSource === self {
      panel.reloadData()
      panel.currentPreviewItemIndex = index
      return
    }
    // Front, not key: the keys stay with the window and its panel cursor.
    panel.orderFront(nil)
    panel.updateController()
    if panel.dataSource !== self {
      // No key window to find the controller through (the app is not the
      // active one): the panel is ours all the same.
      begin(panel)
    } else {
      panel.reloadData()
      panel.currentPreviewItemIndex = index
    }
  }

  /// Closes the panel without telling Dart, which asked for it or is told
  /// by the caller.
  private func closeQuickLook() {
    showing = false
    guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.isVisible
    else { return }
    panel.orderOut(nil)
  }

  /// Whether the window takes the panel's control: only while Dart has it
  /// open.
  var acceptsQuickLook: Bool { showing }

  func begin(_ panel: QLPreviewPanel) {
    panel.dataSource = self
    panel.delegate = self
    panel.reloadData()
    panel.currentPreviewItemIndex = index
  }

  /// The window lost the panel: closed by the user, or another window
  /// (another application) took the keys. Either way it closes, so it
  /// never comes back empty when the app is active again.
  func end(_ panel: QLPreviewPanel) {
    panel.dataSource = nil
    panel.delegate = nil
    if showing {
      showing = false
      channel.invokeMethod("quickLook.closed", arguments: nil)
      DispatchQueue.main.async {
        if panel.isVisible { panel.orderOut(nil) }
      }
    }
  }

  /// The panel's own close button (it is a window and we its delegate).
  func windowWillClose(_ notification: Notification) {
    if showing {
      showing = false
      channel.invokeMethod("quickLook.closed", arguments: nil)
    }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    items.count
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    items[min(max(index, 0), items.count - 1)] as NSURL
  }

  /// Keys pressed while the panel has them (the user clicked it).
  func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
    guard let event = event, event.type == .keyDown else { return false }
    let command = event.modifierFlags.contains(.command)
    switch (event.keyCode, command) {
    case (125, false):  // ↓
      channel.invokeMethod("quickLook.step", arguments: ["delta": 1])
      return true
    case (126, false):  // ↑
      channel.invokeMethod("quickLook.step", arguments: ["delta": -1])
      return true
    case (49, false), (53, false), (16, true):  // Space, Esc, ⌘Y
      closeQuickLook()
      channel.invokeMethod("quickLook.closed", arguments: nil)
      return true
    default:
      return false
    }
  }

  // MARK: - Share

  /// The picker for [paths], pointing at [rect] (Flutter's logical
  /// coordinates: points from the view's top left).
  private func share(paths: [String], rect: [Double]) {
    guard let view = view, !paths.isEmpty, rect.count == 4 else { return }
    let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
    let width = max(rect[2], 1)
    let height = max(rect[3], 1)
    let y = view.isFlipped ? rect[1] : view.bounds.height - rect[1] - height
    let anchor = NSRect(x: rect[0], y: y, width: width, height: height)
    let picker = NSSharingServicePicker(items: urls)
    self.picker = picker
    // Under the anchor, as a menu opens under its row.
    picker.show(relativeTo: anchor, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
  }
}
