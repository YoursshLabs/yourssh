import 'package:flutter/material.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'screens/snippets_screen.dart';

class YourSSHSnippetsPlugin extends YourSSHPlugin {
  /// Stable plugin ID, usable without an instance (e.g. enabled checks in the host app).
  static const String pluginId = 'dev.yourssh.snippets';

  @override
  String get id => pluginId;

  @override
  String get name => 'Snippets';

  @override
  String get description => 'Save and recall reusable shell commands.';

  @override
  IconData get icon => Icons.code;

  @override
  String get version => '1.0.0';

  @override
  String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    return SnippetsScreen(pluginContext: pluginContext);
  }
}
