import Flutter
import UIKit

/// Native entry point for YourSSH on iOS. Method channels (Keychain access,
/// app lock, file import, ...) are added here by later tasks; for now it only
/// registers itself for UIScene lifecycle callbacks.
final class YourSshNative: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = YourSshNative()
    // Ownership: nothing else keeps `instance` alive. Flutter holds scene
    // lifecycle delegates in a WEAK array, so without a strong reference it
    // would be deallocated as soon as this function returns (and every channel
    // call would then fail). `publish` retains it for the registrar's lifetime
    // and `addMethodCallDelegate` makes the channel retain it as its handler.
    registrar.publish(instance)
    registrar.addSceneDelegate(instance)

    // yourssh/background: begin -> {"id": Int, "remainingMs": Int} (-1 when the
    // OS reports no finite allowance), null when refused; end(id).
    let background = FlutterMethodChannel(
      name: "yourssh/background", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: background)

    // yourssh/files: excludeFromBackup(path) -> null. Marks a file or directory
    // as not to be included in iCloud / iTunes backups.
    let files = FlutterMethodChannel(
      name: "yourssh/files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: files)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "begin": beginBackgroundTask(result)
    case "end":
      if let id = call.arguments as? Int { endBackgroundTask(id) }
      result(nil)
    case "excludeFromBackup": excludeFromBackup(call.arguments, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func beginBackgroundTask(_ result: @escaping FlutterResult) {
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

  private func excludeFromBackup(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let path = arguments as? String else {
      result(FlutterError(code: "bad_args", message: "path expected", details: nil))
      return
    }
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      result(nil)
    } catch {
      result(FlutterError(code: "exclude_failed", message: "\(error)", details: nil))
    }
  }
}
