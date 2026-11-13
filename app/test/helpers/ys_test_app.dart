import 'package:flutter/material.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Test host that mirrors the real app root: Material theme plus the
/// FTheme/FToaster wrapping from [ysRootBuilder] / [ysRootBuilderTouch].
Widget ysTestApp(Widget child, {bool touch = false}) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: touch ? ysRootBuilderTouch : ysRootBuilder,
  home: Scaffold(body: child),
);
