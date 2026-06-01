import Cocoa
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

    super.awakeFromNib()
  }
}
