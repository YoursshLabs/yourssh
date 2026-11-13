import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String job(String y, String name) {
  final start = y.indexOf('\n  $name:');
  final next =
      RegExp(r'\n  [a-z][a-z0-9-]*:\n').firstMatch(y.substring(start + 1));
  return next == null ? y.substring(start) : y.substring(start, start + 1 + next.start);
}

void main() {
  test('release.yml has a gated build-ios job that stays off the GitHub release',
      () {
    final y = File('../.github/workflows/release.yml').readAsStringSync();
    final ios = job(y, 'build-ios');
    expect(ios, contains('needs: test'));
    expect(ios, contains('IOS_SIGNING:'));
    expect(ios, contains("if: env.IOS_SIGNING == 'true'"));
    expect(ios, contains('check_ios_bundle.sh'));
    expect(ios, contains('ASC_KEY_ID'));
    expect(ios, contains('if: always()'));
    expect(ios, contains('github.run_attempt'));
    expect(ios, isNot(contains('--build-number=\${{ github.run_number }}')));
    expect(ios, contains('--build-number="\$BUILD_NUMBER"'));
    expect(job(y, 'release'), isNot(contains('build-ios')));
    expect(ios, contains('::add-mask::\$KEYCHAIN_PASSWORD'));
    expect(ios.indexOf('SIGN_KEYCHAIN='),
        lessThan(ios.indexOf('security import')));
    expect(ios.indexOf('Name the IPA'), lessThan(ios.indexOf('altool')));
    expect(ios, contains("if: always() && env.IOS_SIGNING == 'true'"));
    final opts = File('ios/ExportOptions.plist').readAsStringSync();
    expect(opts, allOf(contains('84T567KMYD'), contains('app-store-connect')));
  });

  test('profile name is consistent across workflow, export options, project',
      () {
    const name = 'YourSSH App Store';
    final y = File('../.github/workflows/release.yml').readAsStringSync();
    final opts = File('ios/ExportOptions.plist').readAsStringSync();
    final pbx =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(job(y, 'build-ios'), contains(name));
    expect(opts, contains('<string>$name</string>'));
    expect(opts, contains('com.thangnm.yourssh'));
    expect(pbx, contains('PROVISIONING_PROFILE_SPECIFIER = "$name";'));
    expect(pbx, contains('CODE_SIGN_STYLE = Manual;'));
  });
}
