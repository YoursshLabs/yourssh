import 'package:flutter/material.dart';

/// Widget slots for DevOps sub-screens that depend on app-level providers
/// (SessionProvider, SshService, TunnelProvider). Passed from the app so
/// the yourssh_devops package stays free of circular dependencies.
class DevOpsPluginConfig {
  final Widget networkToolsScreen;
  final Widget cloudflareScreen;
  final Widget mailCatcherScreen;
  final Widget mcpServerScreen;

  const DevOpsPluginConfig({
    required this.networkToolsScreen,
    required this.cloudflareScreen,
    required this.mailCatcherScreen,
    required this.mcpServerScreen,
  });
}
