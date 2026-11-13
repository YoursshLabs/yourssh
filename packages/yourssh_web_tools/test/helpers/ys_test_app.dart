// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Test host mirroring the app root: Material theme plus the FTheme/FToaster
/// wrapping the app's `ysRootBuilder` provides.
Widget ysTestApp(Widget child) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) => FTheme(
    data: ysThemeData(),
    child: FToaster(child: child ?? const SizedBox.shrink()),
  ),
  home: Scaffold(body: child),
);
