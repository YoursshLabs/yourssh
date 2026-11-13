import Flutter
import UIKit

/// Native entry point for YourSSH on iOS. Method channels (Keychain access,
/// app lock, file import, ...) are added here by later tasks; for now it only
/// registers itself for UIScene lifecycle callbacks.
final class YourSshNative: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = YourSshNative()
    registrar.addSceneDelegate(instance)
  }
}
