import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Info.plist and privacy manifest carry the required entries', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final k in [
      'NSCameraUsageDescription',
      'NSLocalNetworkUsageDescription',
      'NSFaceIDUsageDescription',
      'UIFileSharingEnabled',
      'LSSupportsOpeningDocumentsInPlace',
    ]) {
      expect(plist, contains('<key>$k</key>'));
    }
    expect(
        plist,
        matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<true/>',
            dotAll: true)));
    expect(plist, isNot(contains('NSAppTransportSecurity')));
    final pm = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(pm, contains('<key>NSPrivacyTracking</key>'));
    expect(pm, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
    expect(pm, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(pm, contains('CA92.1'));
    expect(pm, contains('C617.1'));
    expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PrivacyInfo.xcprivacy in Resources'));
  });
}
