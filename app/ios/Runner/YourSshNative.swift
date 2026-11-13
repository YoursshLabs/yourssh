import Flutter
import UIKit

/// Native entry point for YourSSH on iOS. Method channels (Keychain access,
/// app lock, file import, ...) are added here by later tasks; for now it only
/// registers itself for UIScene lifecycle callbacks.
final class YourSshNative: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]

  /// A link channel with the macOS contract (MainFlutterWindow.swift): Dart
  /// calls `ready`, native calls `open(String)`. URLs arriving before `ready`
  /// (a cold launch) are queued, newest 8 kept.
  private final class LinkChannel {
    let channel: FlutterMethodChannel
    private var dartReady = false
    private var pending: [String] = []

    init(_ channel: FlutterMethodChannel) { self.channel = channel }

    func ready() {
      dartReady = true
      let queued = pending
      pending.removeAll()
      for url in queued { channel.invokeMethod("open", arguments: url) }
    }

    func deliver(_ url: String) {
      if dartReady {
        channel.invokeMethod("open", arguments: url)
      } else {
        pending.append(url)
        if pending.count > 8 { pending.removeFirst(pending.count - 8) }
      }
    }
  }

  private var yoursshLinks: LinkChannel?
  private var sshLinks: LinkChannel?

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

    // yourssh/url (yourssh://) and yourssh/ssh_url (ssh://): Dart -> native
    // `ready`; native -> Dart `open`.
    let url = FlutterMethodChannel(
      name: "yourssh/url", binaryMessenger: registrar.messenger())
    let sshUrl = FlutterMethodChannel(
      name: "yourssh/ssh_url", binaryMessenger: registrar.messenger())
    instance.yoursshLinks = LinkChannel(url)
    instance.sshLinks = LinkChannel(sshUrl)
    // One handler per channel (the delegate's `handle` cannot tell which
    // channel a call came from). The closures keep their LinkChannel alive.
    for link in [instance.yoursshLinks!, instance.sshLinks!] {
      link.channel.setMethodCallHandler { call, result in
        if call.method == "ready" {
          link.ready()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // MARK: Links

  /// Cold start: the launching URL arrives in the connection options.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return routeLinks(contexts)
  }

  /// Warm start: the app is already running.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return routeLinks(URLContexts)
  }

  /// Returns true when a link was ours. Claiming it keeps Flutter from also
  /// treating the URL as a navigation route.
  private func routeLinks(_ contexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in contexts {
      let url = context.url.absoluteString
      switch context.url.scheme?.lowercased() {
      case "yourssh": yoursshLinks?.deliver(url); handled = true
      case "ssh": sshLinks?.deliver(url); handled = true
      default: break
      }
    }
    return handled
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
