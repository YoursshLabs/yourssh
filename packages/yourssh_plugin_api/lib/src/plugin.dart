import 'package:flutter/material.dart';
import 'plugin_context.dart';

abstract class YourSSHPlugin {
  /// Reverse-domain unique ID, e.g. "dev.yourssh.devops"
  String get id;
  String get name;
  String get description;
  IconData get icon;
  String get version;

  /// Minimum yourssh_plugin_api version required, e.g. "1.0.0"
  String get minApiVersion;

  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext);

  void onActivate(YourSSHPluginContext ctx) {}
  void onDeactivate() {}
}
