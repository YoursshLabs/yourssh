import 'package:flutter/material.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'devops_plugin_config.dart';
import 'screens/devops_hub_screen.dart';

class YourSSHDevOpsPlugin extends YourSSHPlugin {
  final DevOpsPluginConfig config;

  YourSSHDevOpsPlugin({required this.config});

  @override String get id => 'dev.yourssh.devops';
  @override String get name => 'DevOps Hub';
  @override String get description =>
      'Network tools, S3 browser, LAN share, Mail catcher, MCP server, Cloudflare tunnels';
  @override IconData get icon => Icons.rocket_launch_outlined;
  @override String get version => '1.0.0';
  @override String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    return DevOpsHubScreen(config: config);
  }
}
