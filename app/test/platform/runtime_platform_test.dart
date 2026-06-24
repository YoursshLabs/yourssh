import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/platform/runtime_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('isMobilePlatform is true on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isMobilePlatform, isTrue);
  });

  test('isMobilePlatform is true on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isMobilePlatform, isTrue);
  });

  test('isMobilePlatform is false on macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isMobilePlatform, isFalse);
  });

  test('isMobilePlatform is false on Windows and Linux', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(isMobilePlatform, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isMobilePlatform, isFalse);
  });
}
