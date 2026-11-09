import Flutter
import UIKit

public final class NativeTextSelectionPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let capabilities = FlutterMethodChannel(
      name: "io.github.abra.native_text_selection/capabilities",
      binaryMessenger: registrar.messenger()
    )
    capabilities.setMethodCallHandler { call, result in
      guard call.method == "isAvailable" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 17.0, *) { result(true) } else { result(false) }
    }
    registrar.register(
      NativeSelectionFactory(messenger: registrar.messenger()),
      withId: nativeSelectionViewType
    )
  }
}

let nativeSelectionViewType = "io.github.abra.native_text_selection/surface"

private final class NativeSelectionFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeSelectionPlatformView(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "\(nativeSelectionViewType)/\(viewId)",
        binaryMessenger: messenger
      ),
      arguments: args as? [String: Any]
    )
  }
}

private final class NativeSelectionPlatformView: NSObject, FlutterPlatformView {
  private let selectionView: NativeSelectionView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]?) {
    self.channel = channel
    selectionView = NativeSelectionView(frame: frame)
    super.init()
    selectionView.onEvent = { [weak channel] method, arguments in
      channel?.invokeMethod(method, arguments: arguments)
    }
    if let arguments { selectionView.update(arguments) }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing snapshot", details: nil))
          return
        }
        result(self.selectionView.update(arguments))
      case "select":
        guard let arguments = call.arguments as? [String: Any],
          let base = arguments["base"] as? Int,
          let extent = arguments["extent"] as? Int
        else {
          result(FlutterError(code: "invalid_arguments", message: "Missing selection", details: nil))
          return
        }
        self.selectionView.select(base: base, extent: extent, notify: false)
        result(nil)
      case "clear":
        self.selectionView.clear(notify: false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { selectionView }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
