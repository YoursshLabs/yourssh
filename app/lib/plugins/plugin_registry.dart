import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_devops/yourssh_devops.dart';
import 'package:yourssh_web_tools/yourssh_web_tools.dart';
import '../widgets/devops_tools_screen.dart';
import '../widgets/cloudflare_tunnel_screen.dart';
import '../widgets/mail_catcher_screen.dart';
import '../widgets/mcp_server_screen.dart';
import '../widgets/web_tools/port_forward_browser.dart';

/// All plugins compiled into this build.
/// To add a plugin: add it to pubspec.yaml, import above, add an instance here.
final List<YourSSHPlugin> kRegisteredPlugins = [
  YourSSHDevOpsPlugin(
    config: DevOpsPluginConfig(
      networkToolsScreen: const DevopsToolsScreen(),
      cloudflareScreen: const CloudflareTunnelScreen(),
      mailCatcherScreen: const MailCatcherScreen(),
      mcpServerScreen: const McpServerScreen(),
    ),
  ),
  YourSSHWebToolsPlugin(
    config: WebToolsPluginConfig(
      portForwardBrowserBuilder: (onOpenUrl) => PortForwardBrowser(onOpenUrl: onOpenUrl),
    ),
  ),
];
