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
