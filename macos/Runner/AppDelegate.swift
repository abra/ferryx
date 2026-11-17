import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationPending = false

  override func applicationShouldTerminate(_ sender: NSApplication)
    -> NSApplication.TerminateReply
  {
    if terminationPending { return .terminateLater }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return .terminateNow }

    // Keep repeated Quit requests pending until Flutter's async checkpoint completes.
    terminationPending = true
    let platform = FlutterMethodChannel(
      name: "flutter/platform", binaryMessenger: controller.engine.binaryMessenger,
      codec: FlutterJSONMethodCodec.sharedInstance())
    platform.invokeMethod("System.requestAppExit", arguments: nil) { [weak self] result in
      DispatchQueue.main.async {
        self?.terminationPending = false
        let response = result as? [String: String]
        sender.reply(toApplicationShouldTerminate: response?["response"] != "cancel")
      }
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
