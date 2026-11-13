import Flutter
import UIKit

/// Native entry point for YourSSH on iOS. Method channels (Keychain access,
/// app lock, file import, ...) are added here by later tasks; for now it only
/// registers itself for UIScene lifecycle callbacks.
final class YourSshNative: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = YourSshNative()
    registrar.addSceneDelegate(instance)

    // yourssh/background: begin -> {"id": Int, "remainingMs": Int} (-1 when the
    // OS reports no finite allowance); end(id). Null result when refused.
    let background = FlutterMethodChannel(
      name: "yourssh/background", binaryMessenger: registrar.messenger())
    background.setMethodCallHandler { [weak instance] call, result in
      guard let instance = instance else { return result(nil) }
      switch call.method {
      case "begin": instance.beginBackgroundTask(result)
      case "end":
        if let id = call.arguments as? Int { instance.endBackgroundTask(id) }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginBackgroundTask(_ result: FlutterResult) {
    var taskId = UIBackgroundTaskIdentifier.invalid
    taskId = UIApplication.shared.beginBackgroundTask(withName: "yourssh.grace") { [weak self] in
      // The OS is about to suspend us: end the task so it does not kill the app.
      self?.endBackgroundTask(taskId.rawValue)
    }
    if taskId == .invalid {
      result(nil)
      return
    }
    backgroundTasks[taskId.rawValue] = taskId
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let remainingMs = remaining.isFinite && remaining < Double(Int32.max)
      ? Int(remaining * 1000) : -1
    result(["id": taskId.rawValue, "remainingMs": remainingMs])
  }

  private func endBackgroundTask(_ id: Int) {
    guard let task = backgroundTasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(task)
  }
}
