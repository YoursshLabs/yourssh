import 'package:flutter/foundation.dart';

/// True when running on a mobile platform (Android/iOS).
///
/// Drives the desktop-vs-mobile branch in `main()` and gates the desktop-only
/// bootstrap (window_manager / hotkey_manager / local_notifier). Uses
/// [defaultTargetPlatform] (not `dart:io` `Platform`) so it is overridable in
/// widget/unit tests via `debugDefaultTargetPlatformOverride`.
bool get isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// True on iOS; consumed by the iOS-specific branches (no subprocess, App Store rules).
bool get isIOSPlatform => defaultTargetPlatform == TargetPlatform.iOS;

/// Whether RDP/VNC tabs are offered; consumed by the host editor and dashboard (mobile until phase 3).
bool get supportsRemoteDesktop => !isMobilePlatform;

/// Whether the platform can spawn child processes (local shell, ssh-keygen, cloudflared); false on iOS.
bool get supportsSubprocesses => !isIOSPlatform;

/// Whether tmux persistence is on by default (flaky mobile links); consumed by SettingsProvider.
bool get mobileDefaultTmux => isMobilePlatform;
