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

  test('iOS: no subprocesses or remote desktop; tmux default on', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isIOSPlatform, isTrue);
    expect(supportsSubprocesses, isFalse);
    expect(supportsRemoteDesktop, isFalse);
    expect(mobileDefaultTmux, isTrue);
  });

  test('Android: subprocesses yes, remote desktop no, tmux default on', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isIOSPlatform, isFalse);
    expect(supportsSubprocesses, isTrue);
    expect(supportsRemoteDesktop, isFalse);
    expect(mobileDefaultTmux, isTrue);
  });

  test('macOS keeps every desktop capability', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isIOSPlatform, isFalse);
    expect(supportsSubprocesses && supportsRemoteDesktop, isTrue);
    expect(mobileDefaultTmux, isFalse);
  });
}
