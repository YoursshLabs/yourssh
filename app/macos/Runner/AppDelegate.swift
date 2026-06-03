import Cocoa
import CoreServices
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController
            as? FlutterViewController else { return }

    let channel = FlutterMethodChannel(
      name: "yourssh/app_discovery",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "getAppsFor",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let fileURL = URL(fileURLWithPath: path) as CFURL
      // LSCopyApplicationURLsForURL is available since macOS 10.3
      // and works with the 10.15 deployment target.
      guard let cfApps = LSCopyApplicationURLsForURL(fileURL, .all)?
              .takeRetainedValue() as? [URL] else {
        result([[String]]())
        return
      }
      let mapped: [[String]] = cfApps.map { appURL in
        let bundle = Bundle(url: appURL)
        let name = bundle?.infoDictionary?["CFBundleName"] as? String
          ?? appURL.deletingPathExtension().lastPathComponent
        let bundleId = bundle?.bundleIdentifier ?? ""
        var iconPath = ""
        if let resourceURL = bundle?.resourceURL,
           let iconFile = bundle?.infoDictionary?["CFBundleIconFile"] as? String {
          var icon = iconFile
          if !icon.hasSuffix(".icns") { icon += ".icns" }
          iconPath = resourceURL.appendingPathComponent(icon).path
        }
        return [name, bundleId, appURL.path, iconPath]
      }
      result(mapped)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication) -> Bool { return true }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication) -> Bool { return true }
}
