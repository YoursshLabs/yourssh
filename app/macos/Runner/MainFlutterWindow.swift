import Cocoa
import CoreServices
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set a larger default window size and center it on screen.
    let targetSize = NSSize(width: 1280, height: 800)
    if let screenFrame = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
      let originX = screenFrame.origin.x + (screenFrame.width - targetSize.width) / 2
      let originY = screenFrame.origin.y + (screenFrame.height - targetSize.height) / 2
      self.setFrame(NSRect(x: originX, y: originY, width: targetSize.width, height: targetSize.height), display: true)
    } else {
      self.setContentSize(targetSize)
    }
    self.minSize = NSSize(width: 1100, height: 700)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerAppDiscoveryChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Registers the `yourssh/app_discovery` method channel used by the SFTP
  /// "Open with" submenu to list applications that can open a given file.
  /// Lives here (not AppDelegate) because awakeFromNib is where the
  /// FlutterViewController is created — applicationDidFinishLaunching is not
  /// reliably invoked in this app.
  private func registerAppDiscoveryChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yourssh/app_discovery",
      binaryMessenger: messenger)

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
}
