import 'package:flutter/material.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show YsPluginHost, FLucideIcons;
import 'screens/web_tools_screen.dart';
import 'web_tools_plugin_config.dart';

class YourSSHWebToolsPlugin extends YourSSHPlugin {
  final WebToolsPluginConfig config;

  YourSSHWebToolsPlugin({required this.config});

  @override
  String get id => 'dev.yourssh.webtools';

  @override
  String get name => 'Web Tools';

  @override
  String get description => 'Embedded browser, HTTP client, and port-forward browser.';

  @override
  IconData get icon => FLucideIcons.wrench;

  @override
  String get version => '1.0.0';

  @override
  String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    return YsPluginHost(child: WebToolsScreen(config: config));
  }
}
