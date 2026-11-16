import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner config', () {
    final proj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(proj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.thangnm.yourssh;'));
    Set<String> all(String key) => RegExp('$key = "?([^";]+)"?;')
        .allMatches(proj)
        .map((m) => m[1]!)
        .toSet();
    expect(all('IPHONEOS_DEPLOYMENT_TARGET'), {'16.0'});
    expect(all('TARGETED_DEVICE_FAMILY'), {'1'});
    expect(proj, contains('DEVELOPMENT_TEAM = 84T567KMYD;'));
    expect(proj, contains('YourSshNative.swift in Sources'));
    expect(File('ios/Podfile').readAsStringSync(),
        contains("\nplatform :ios, '16.0'"));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
        plist,
        matches(RegExp(
            r'<key>CFBundleDisplayName</key>\s*<string>YourSSH</string>')));
    expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
    expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        allOf(contains('didInitializeImplicitFlutterEngine'),
            contains('YourSshNative.register')));
    final lock = File('ios/Podfile.lock');
    if (lock.existsSync()) {
      expect(lock.readAsStringSync(), isNot(contains('GoogleMLKit')));
    }
  });
}
